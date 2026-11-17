require "rails_helper"

RSpec.describe "Store listing lifecycle", type: :request do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:store_app) { create(:apple_app, organization: organization) }
  let(:release_id) { "apple_app_#{store_app.id}" }
  let!(:english) { create(:store_listing, :synced, organization: organization, listable: store_app, locale: "en-US") }
  let!(:german) { create(:store_listing, organization: organization, listable: store_app, locale: "de-DE") }

  before do
    sign_in user, scope: :user
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  def status
    get sync_status_organization_release_path(organization, release_id), as: :json
    response.parsed_body
  end

  it "tracks the queued sync independently of old listing timestamps, including an empty import" do
    post sync_organization_release_path(organization, release_id), as: :json
    id = response.parsed_body.dig("operation", "id")
    expect(id).to be_present
    expect(status.dig("sync_operation", "status")).to eq("queued")
    importer = instance_double(StoreListingSync::AppleImporter, import!: [])
    allow(StoreListingSync::AppleImporter).to receive(:new).and_return(importer)
    perform_enqueued_jobs(only: StoreListingSyncJob)
    expect(status["sync_operation"]).to include("id" => id, "status" => "completed")
  end

  it "deduplicates repeated sync requests and rejects a push during sync" do
    post sync_organization_release_path(organization, release_id), as: :json
    expect { post sync_organization_release_path(organization, release_id), as: :json }
      .not_to have_enqueued_job(StoreListingSyncJob)
    expect { post push_organization_release_path(organization, release_id), as: :json }
      .not_to have_enqueued_job(StoreListingBatchPushJob)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "queues one sequential push batch, rejects a duplicate, and waits for every locale" do
    expect { post push_organization_release_path(organization, release_id), as: :json }
      .to have_enqueued_job(StoreListingBatchPushJob).with(organization_id: organization.id, store_listing_ids: [ english.id, german.id ])
    expect { post push_organization_release_path(organization, release_id), as: :json }
      .not_to have_enqueued_job(StoreListingBatchPushJob)
    english.update!(push_status: "success")
    expect(status["push_status"]).to eq("pushing")
    german.update!(push_status: "failed", push_error: "Store unavailable")
    expect(status).to include("push_status" => "failed", "push_error" => "de-DE: Store unavailable")
    get organization_release_path(organization, release_id, locale: "en-US")
    expect(response.body).to include("de-DE: Store unavailable")
    expect(english.reload.push_status).to eq("success")
  end

  it "keeps skipped-field warnings after reopening another locale" do
    german.update!(sync_status: "partially_synced", push_status: "partial_success", push_fields_skipped: [ "keywords" ])
    get organization_release_path(organization, release_id, locale: "en-US")
    get organization_release_path(organization, release_id, locale: "de-DE")
    expect(response.body).to include("Some fields were not pushed", "de-DE: keywords")
    expect(german.reload.push_fields_skipped).to eq([ "keywords" ])
    expect(status["push_status"]).to eq("partial_success")
  end

  it "rejects platform-invalid locale codes without creating a row" do
    expect { post add_locale_organization_release_path(organization, release_id), params: { locale: "ja-JP" } }
      .not_to change(StoreListing, :count)
    expect(flash[:alert]).to include("not supported")
  end

  it "validates the store locale when creating the first listing too" do
    android = create(:android_app, organization: organization)
    expect do
      post create_listing_organization_release_path(organization, "android_app_#{android.id}"), params: { locale: "ja" }
    end.not_to change(StoreListing, :count)
    expect(flash[:alert]).to include("not supported")
  end

  it "persists translation progress through reloads and deduplicates repeated clicks" do
    expect { post translate_organization_release_path(organization, release_id), params: { locale: "de-DE" } }
      .to have_enqueued_job(StoreListingTranslationJob)
    expect(german.reload).to be_translation_pending
    expect { post translate_organization_release_path(organization, release_id), params: { locale: "de-DE" } }
      .not_to have_enqueued_job(StoreListingTranslationJob)
    get organization_release_path(organization, release_id, locale: "de-DE")
    expect(response.body).to include("Translating&hellip;")
  end

  it "enforces the locale limit on the server" do
    user.update!(plan_tier: :free)
    expect { post add_locale_organization_release_path(organization, release_id), params: { locale: "fr-FR" } }
      .not_to change(StoreListing, :count)
    expect(flash[:alert]).to include("limit of 1 locale")
  end

  it "returns a useful autosave validation error for a URL without a host" do
    patch organization_release_path(organization, release_id, locale: "en-US"),
      params: { store_listing: { support_url: "https:" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["errors"]).to include("Support url must be a valid HTTP or HTTPS URL")
    expect(english.reload.support_url).not_to eq("https:")
  end
end
