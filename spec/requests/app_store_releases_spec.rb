require "rails_helper"

# CLI Defaults (formerly "Release Configuration") web UI request specs.
# Despite the route name being `app_store_releases` for backward compatibility,
# the controller now operates on `apple_apps.cli_defaults` JSONB — the legacy
# AppStoreRelease model has been retired.
RSpec.describe "AppStoreReleases (CLI Defaults web UI)", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:bundle_id) do
    AppleBundleId.create!(
      organization: organization,
      remote_id: "ABC123",
      identifier: "com.example.testapp",
      name: "Test App",
      platform: "IOS"
    )
  end
  let!(:apple_app) do
    organization.apple_apps.create!(
      app_store_id: "123456",
      name: "Test App",
      bundle_id: "com.example.testapp"
    )
  end

  before do
    sign_in user
  end

  describe "GET /organizations/:organization_id/app_store_releases/new" do
    it "renders the new form" do
      get new_organization_app_store_release_path(organization, bundle_id_id: bundle_id.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("CLI Defaults")
      expect(response.body).to include("Version")
      expect(response.body).to include("Release Strategy")
    end

    it "redirects to edit if CLI defaults already exist" do
      apple_app.update!(cli_defaults: { "release_type" => "AFTER_APPROVAL", "auto_submit" => true })

      get new_organization_app_store_release_path(organization, bundle_id_id: bundle_id.id)

      expect(response).to redirect_to(edit_organization_app_store_release_path(organization, apple_app))
    end

    it "redirects with alert when no matching AppleApp exists" do
      other_bundle = AppleBundleId.create!(
        organization: organization,
        remote_id: "XYZ789",
        identifier: "com.example.no-app",
        name: "No App",
        platform: "IOS"
      )

      get new_organization_app_store_release_path(organization, bundle_id_id: other_bundle.id)

      expect(response).to redirect_to(organization_apple_apps_path(organization))
    end
  end

  describe "POST /organizations/:organization_id/app_store_releases" do
    context "with valid params" do
      let(:valid_params) do
        {
          app_store_release: {
            apple_bundle_id_id: bundle_id.id,
            auto_submit: "1",
            phased_release: "1",
            version_string: "2.0.0",
            build_number: "100",
            release_type: "AFTER_APPROVAL"
          }
        }
      end

      it "writes cli_defaults and redirects" do
        post organization_app_store_releases_path(organization), params: valid_params

        expect(response).to have_http_status(:redirect)
        apple_app.reload
        expect(apple_app.cli_defaults["auto_submit"]).to eq(true)
        expect(apple_app.cli_defaults["phased_release"]).to eq(true)
        expect(apple_app.cli_defaults["version_string"]).to eq("2.0.0")
        expect(apple_app.cli_defaults["build_number"]).to eq("100")
        expect(apple_app.cli_defaults["release_type"]).to eq("AFTER_APPROVAL")
        follow_redirect!
        expect(response.body).to include("successfully")
      end

      it "creates release with MANUAL release type" do
        params = valid_params.deep_merge(app_store_release: { release_type: "MANUAL" })
        post organization_app_store_releases_path(organization), params: params

        expect(apple_app.reload.cli_defaults["release_type"]).to eq("MANUAL")
      end

      it "creates release with SCHEDULED release type and date" do
        scheduled_date = 2.days.from_now
        params = valid_params.deep_merge(
          app_store_release: {
            release_type: "SCHEDULED",
            earliest_release_date: scheduled_date.iso8601
          }
        )
        post organization_app_store_releases_path(organization), params: params

        apple_app.reload
        expect(apple_app.cli_defaults["release_type"]).to eq("SCHEDULED")
        expect(Time.zone.parse(apple_app.cli_defaults["earliest_release_date"]))
          .to be_within(1.second).of(scheduled_date)
      end
    end

    context "with invalid params" do
      it "renders errors for SCHEDULED without date" do
        post organization_app_store_releases_path(organization), params: {
          app_store_release: {
            apple_bundle_id_id: bundle_id.id,
            release_type: "SCHEDULED"
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to match(/earliest.*(blank|required)/i)
                                 .or include("can't be blank")
      end

      it "renders errors for invalid build_number" do
        post organization_app_store_releases_path(organization), params: {
          app_store_release: {
            apple_bundle_id_id: bundle_id.id,
            build_number: "abc"
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to match(/build[_ ]number/i).or include("is not a number")
      end
    end
  end

  describe "GET /organizations/:organization_id/app_store_releases/:id/edit" do
    before do
      apple_app.update!(cli_defaults: {
        "auto_submit" => true,
        "phased_release" => true,
        "version_string" => "1.5.0",
        "build_number" => "50",
        "release_type" => "MANUAL"
      })
    end

    it "renders the edit form with existing values" do
      get edit_organization_app_store_release_path(organization, apple_app)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("1.5.0")
      expect(response.body).to include("50")
      expect(response.body).to include("CLI Defaults")
    end

    it "shows auto_submit as enabled in the badge" do
      get edit_organization_app_store_release_path(organization, apple_app)

      expect(response.body).to include("Auto-submit enabled")
    end
  end

  describe "PATCH /organizations/:organization_id/app_store_releases/:id" do
    before do
      apple_app.update!(cli_defaults: {
        "release_type" => "AFTER_APPROVAL",
        "auto_submit" => false
      })
    end

    context "with valid params" do
      it "updates cli_defaults and redirects" do
        patch organization_app_store_release_path(organization, apple_app), params: {
          app_store_release: { auto_submit: "1" }
        }

        expect(response).to have_http_status(:redirect)
        expect(apple_app.reload.cli_defaults["auto_submit"]).to eq(true)
      end

      it "updates all strategy fields correctly" do
        patch organization_app_store_release_path(organization, apple_app), params: {
          app_store_release: {
            auto_submit: "0",
            phased_release: "1",
            version_string: "2.0.0",
            release_type: "MANUAL"
          }
        }

        apple_app.reload
        expect(apple_app.cli_defaults["auto_submit"]).to eq(false)
        expect(apple_app.cli_defaults["phased_release"]).to eq(true)
        expect(apple_app.cli_defaults["version_string"]).to eq("2.0.0")
        expect(apple_app.cli_defaults["release_type"]).to eq("MANUAL")
      end

      it "updates to SCHEDULED with date" do
        scheduled_date = 3.days.from_now
        patch organization_app_store_release_path(organization, apple_app), params: {
          app_store_release: {
            release_type: "SCHEDULED",
            earliest_release_date: scheduled_date.iso8601
          }
        }

        apple_app.reload
        expect(apple_app.cli_defaults["release_type"]).to eq("SCHEDULED")
        expect(Time.zone.parse(apple_app.cli_defaults["earliest_release_date"]))
          .to be_within(1.second).of(scheduled_date)
      end
    end

    context "with invalid params" do
      it "renders errors for invalid build_number" do
        patch organization_app_store_release_path(organization, apple_app), params: {
          app_store_release: { build_number: "abc" }
        }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /organizations/:organization_id/app_store_releases/:id" do
    before do
      apple_app.update!(cli_defaults: { "auto_submit" => true, "release_type" => "AFTER_APPROVAL" })
    end

    it "clears cli_defaults and redirects" do
      delete organization_app_store_release_path(organization, apple_app)

      expect(response).to have_http_status(:redirect)
      expect(apple_app.reload.cli_defaults).to eq({})
    end
  end

  describe "round-trip: create -> edit -> update" do
    it "preserves all strategy fields across create and edit cycles" do
      post organization_app_store_releases_path(organization), params: {
        app_store_release: {
          apple_bundle_id_id: bundle_id.id,
          auto_submit: "1",
          phased_release: "1",
          version_string: "3.0.0",
          build_number: "200",
          release_type: "MANUAL"
        }
      }

      apple_app.reload

      get edit_organization_app_store_release_path(organization, apple_app)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("3.0.0")
      expect(response.body).to include("200")

      patch organization_app_store_release_path(organization, apple_app), params: {
        app_store_release: { release_type: "AFTER_APPROVAL" }
      }

      apple_app.reload
      expect(apple_app.cli_defaults["auto_submit"]).to eq(true)
      expect(apple_app.cli_defaults["phased_release"]).to eq(true)
      expect(apple_app.cli_defaults["version_string"]).to eq("3.0.0")
      expect(apple_app.cli_defaults["build_number"]).to eq("200")
      expect(apple_app.cli_defaults["release_type"]).to eq("AFTER_APPROVAL")
    end
  end
end
