require "rails_helper"

RSpec.describe "Custom Product Pages", type: :request do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let!(:credential) { create(:app_store_connect_credential, organization: organization) }

  before do
    sign_in user, scope: :user
  end

  describe "GET /organizations/:organization_id/custom_product_pages" do
    it "loads the CPP index" do
      get organization_custom_product_pages_path(organization)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Custom Product Pages")
    end

    it "redirects unauthenticated users" do
      sign_out user
      get organization_custom_product_pages_path(organization)
      expect(response).to redirect_to(new_user_session_path)
    end

    context "with free plan" do
      let(:user) { create(:user, plan_tier: :free) }

      it "shows upgrade prompt" do
        get organization_custom_product_pages_path(organization)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Upgrade to unlock")
      end
    end

    context "with CPPs" do
      let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }

      it "shows CPP cards" do
        get organization_custom_product_pages_path(organization)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(cpp.name)
      end
    end
  end

  describe "GET /organizations/:organization_id/custom_product_pages/:id" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }

    it "shows the CPP detail page" do
      get organization_custom_product_page_path(organization, cpp)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(cpp.name)
    end

    it "shows overview tab by default" do
      get organization_custom_product_page_path(organization, cpp)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Page Settings")
    end

    it "shows screenshots tab" do
      get organization_custom_product_page_path(organization, cpp, tab: "screenshots")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Screenshots")
    end

    it "shows keywords tab" do
      # Mock the keyword fetch
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:keywords).and_return({ "data" => [] })

      get organization_custom_product_page_path(organization, cpp, tab: "keywords")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Assigned to This CPP")
    end

    it "shows performance tab" do
      get organization_custom_product_page_path(organization, cpp, tab: "performance")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No Performance Data Yet")
    end

    context "with performance data" do
      let!(:cpp_with_perf) do
        create(:custom_product_page,
          organization: organization,
          apple_app: apple_app,
          performance_data: { "impressions" => 5000, "downloads" => 250, "conversion_rate" => 0.05 }
        )
      end

      it "shows performance stats" do
        get organization_custom_product_page_path(organization, cpp_with_perf, tab: "performance")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Impressions")
        expect(response.body).to include("Downloads")
        expect(response.body).to include("Conversion Rate")
      end
    end
  end

  describe "GET /organizations/:organization_id/custom_product_pages/new" do
    it "shows the new CPP form" do
      get new_organization_custom_product_page_path(organization)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create Custom Product Page")
    end
  end

  describe "POST /organizations/:organization_id/custom_product_pages" do
    it "creates a CPP via Apple API" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:create).and_return({
        "data" => {
          "id" => "new_cpp_remote",
          "attributes" => { "name" => "Winter Promo", "visible" => true }
        }
      })

      expect {
        post organization_custom_product_pages_path(organization),
          params: { apple_app_id: apple_app.id, name: "Winter Promo", visible: "1" }
      }.to change(CustomProductPage, :count).by(1)

      expect(response).to redirect_to(organization_custom_product_pages_path(organization))
      expect(flash[:notice]).to include("created")
    end

    it "handles API errors gracefully" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:create).and_raise(StandardError, "API limit reached")

      post organization_custom_product_pages_path(organization),
        params: { apple_app_id: apple_app.id, name: "Fail CPP", visible: "1" }

      expect(response).to redirect_to(new_organization_custom_product_page_path(organization))
      expect(flash[:alert]).to include("API limit reached")
    end
  end

  describe "PATCH /organizations/:organization_id/custom_product_pages/:id" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }

    it "updates a CPP via Apple API" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:update)

      patch organization_custom_product_page_path(organization, cpp),
        params: { name: "Updated Name", visible: "1" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp))
      cpp.reload
      expect(cpp.name).to eq("Updated Name")
    end

    it "handles API errors" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:update).and_raise(StandardError, "Forbidden")

      patch organization_custom_product_page_path(organization, cpp),
        params: { name: "Fail", visible: "1" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp, tab: "overview"))
      expect(flash[:alert]).to include("Forbidden")
    end
  end

  describe "DELETE /organizations/:organization_id/custom_product_pages/:id" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }

    it "deletes a CPP via Apple API" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:delete)

      expect {
        delete organization_custom_product_page_path(organization, cpp)
      }.to change(CustomProductPage, :count).by(-1)

      expect(response).to redirect_to(organization_custom_product_pages_path(organization))
      expect(flash[:notice]).to include("deleted")
    end
  end

  describe "POST /organizations/:organization_id/custom_product_pages/:id/sync" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }

    it "enqueues a sync job" do
      post sync_organization_custom_product_page_path(organization, cpp)

      expect(response).to redirect_to(organization_custom_product_pages_path(organization))
      expect(flash[:notice]).to include("sync started")
    end
  end

  describe "POST /organizations/:organization_id/custom_product_pages/:id/add_keyword" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }
    let!(:version) { create(:custom_product_page_version, custom_product_page: cpp, organization: organization) }
    let!(:localization) { create(:custom_product_page_localization, custom_product_page_version: version, organization: organization, locale: "en-US") }

    it "assigns a keyword via Apple API" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:add_keywords)

      post add_keyword_organization_custom_product_page_path(organization, cpp),
        params: { keyword_id: "KW123", locale: "en-US" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp, tab: "keywords"))
      expect(flash[:notice]).to include("assigned")
    end

    it "rejects blank keyword_id" do
      post add_keyword_organization_custom_product_page_path(organization, cpp),
        params: { keyword_id: "" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp, tab: "keywords"))
      expect(flash[:alert]).to include("select")
    end
  end

  describe "DELETE /organizations/:organization_id/custom_product_pages/:id/remove_keyword" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }
    let!(:version) { create(:custom_product_page_version, custom_product_page: cpp, organization: organization) }
    let!(:localization) { create(:custom_product_page_localization, custom_product_page_version: version, organization: organization, locale: "en-US") }

    it "removes a keyword via Apple API" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:remove_keywords)

      delete remove_keyword_organization_custom_product_page_path(organization, cpp),
        params: { keyword_id: "KW123", locale: "en-US" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp, tab: "keywords"))
      expect(flash[:notice]).to include("removed")
    end
  end

  describe "PATCH /organizations/:organization_id/custom_product_pages/:id/update_localization" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }
    let!(:version) { create(:custom_product_page_version, custom_product_page: cpp) }
    let!(:localization) { create(:custom_product_page_localization, custom_product_page_version: version) }

    it "updates promotional text via Apple API" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:update_localization)

      patch update_localization_organization_custom_product_page_path(organization, cpp),
        params: { locale: localization.locale, promotional_text: "New summer promo!" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp, tab: "overview"))
      expect(flash[:notice]).to include("Promotional text updated")
      localization.reload
      expect(localization.promotional_text).to eq("New summer promo!")
    end

    it "handles API errors gracefully" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:update_localization).and_raise(StandardError, "API error")

      patch update_localization_organization_custom_product_page_path(organization, cpp),
        params: { locale: localization.locale, promotional_text: "Fail" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp, tab: "overview"))
      expect(flash[:alert]).to include("Failed to update promotional text")
    end
  end

  describe "PATCH /organizations/:organization_id/custom_product_pages/:id/update_version" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }
    let!(:version) { create(:custom_product_page_version, custom_product_page: cpp) }

    it "updates deep link via Apple API" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:update_version)

      patch update_version_organization_custom_product_page_path(organization, cpp),
        params: { version_id: version.id, deep_link: "myapp://promo/summer" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp, tab: "overview"))
      expect(flash[:notice]).to include("Deep link updated")
      version.reload
      expect(version.deep_link).to eq("myapp://promo/summer")
    end

    it "handles API errors gracefully" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:update_version).and_raise(StandardError, "Forbidden")

      patch update_version_organization_custom_product_page_path(organization, cpp),
        params: { version_id: version.id, deep_link: "myapp://fail" }

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp, tab: "overview"))
      expect(flash[:alert]).to include("Failed to update deep link")
    end
  end

  describe "POST /organizations/:organization_id/custom_product_pages/:id/submit_for_review" do
    let!(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }
    let!(:version) { create(:custom_product_page_version, custom_product_page: cpp, organization: organization, state: "PREPARE_FOR_SUBMISSION") }

    it "submits the CPP for review via Apple's unified review submissions API" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:submit_for_review)

      post submit_for_review_organization_custom_product_page_path(organization, cpp)

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp))
      expect(flash[:notice]).to include("submitted for App Review")
      version.reload
      expect(version.submission_status).to eq("submitted")
      expect(version.submission_error).to be_nil
    end

    it "handles API errors and records failure" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:submit_for_review).and_raise(StandardError, "API error occurred")

      post submit_for_review_organization_custom_product_page_path(organization, cpp)

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp))
      expect(flash[:alert]).to include("Failed to submit for review")
      version.reload
      expect(version.submission_status).to eq("failed")
      expect(version.submission_error).to eq("API error occurred")
    end

    it "humanizes known Apple errors" do
      client = instance_double(AppStoreConnect::Client)
      service = instance_double(AppStoreConnect::CustomProductPages)
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)
      allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
      allow(service).to receive(:submit_for_review).and_raise(StandardError, "no released appStoreVersionLocalization")

      post submit_for_review_organization_custom_product_page_path(organization, cpp)

      version.reload
      expect(version.submission_error).to include("approved and released version")
    end

    it "rejects submission when no draft version exists" do
      version.update!(state: "PUBLISHED")

      post submit_for_review_organization_custom_product_page_path(organization, cpp)

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp))
      expect(flash[:alert]).to include("No draft version found")
    end

    it "rejects submission when already submitted" do
      version.update!(submission_status: "submitted")

      post submit_for_review_organization_custom_product_page_path(organization, cpp)

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp))
      expect(flash[:alert]).to include("cannot be submitted")
    end

    it "rejects submission when no credentials exist" do
      credential.destroy!

      post submit_for_review_organization_custom_product_page_path(organization, cpp)

      expect(response).to redirect_to(organization_custom_product_page_path(organization, cpp))
      expect(flash[:alert]).to include("No active App Store Connect credential")
    end
  end

  describe "authorization" do
    let(:other_user) { create(:user) }
    let(:other_org) { create(:organization, owner: other_user) }

    it "prevents access to other organization's CPPs" do
      get organization_custom_product_pages_path(other_org)
      # 404 (uniform with non-existent ids) prevents the redirect-vs-404
      # enumeration oracle that would expose which org ids exist.
      expect(response).to have_http_status(:not_found)
    end
  end
end
