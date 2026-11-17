require "rails_helper"

RSpec.describe "Dashboard data accuracy", type: :request do
  let(:user) { create(:user, plan_tier: :team) }
  let(:organization) { create(:organization, owner: user) }

  before do
    Rails.cache.clear
    sign_in user
    post switch_organization_path(organization)
  end

  [ :app_store_connect_credential, :google_play_credential ].each do |factory|
    context "with #{factory} history" do
      let(:credential_attributes) do
        attributes = { organization: organization }
        if factory == :google_play_credential
          attributes[:service_account_json] = {
            type: "service_account", project_id: "qa", private_key: "test-key",
            client_email: "qa@example.test", client_id: "123"
          }.to_json
        end
        attributes
      end

      it "shows the active connection, not a more recent inactive failure" do
        create(factory, **credential_attributes, active: true, last_synced_at: 1.hour.ago, last_sync_status: "ok")
        create(factory, **credential_attributes, active: false, last_synced_at: 10.minutes.ago,
          last_sync_status: "error", last_sync_error: "Retired credential failure")

        get authenticated_root_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Retired credential failure")
      end

      it "does not show a disconnected credential's stale failure" do
        create(factory, **credential_attributes, active: false, last_sync_status: "error",
          last_sync_error: "Retired credential failure")

        get authenticated_root_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Retired credential failure")
      end
    end
  end

  describe "analytics date windows" do
    let(:apple_app) { create(:apple_app, organization: organization) }

    def snapshot(days_ago, downloads)
      create(:app_analytics_snapshot, organization: organization, snapshotable: apple_app,
        snapshot_date: Date.current - days_ago, total_downloads: downloads)
    end

    it "respects the Free plan history and omits an unavailable comparison" do
      user.update!(plan_tier: :free)
      snapshot(0, 137)
      snapshot(6, 100)
      snapshot(7, 8_000)
      snapshot(20, 9_000)

      get authenticated_root_path

      expect(response.body).to include("237", "last 7 days", "7d")
      expect(response.body).not_to include("17,237", "vs prev 7d", "vs prev 30d")
    end

    it "uses adjacent non-overlapping periods and excludes future dates" do
      snapshot(0, 100)
      snapshot(29, 100)
      snapshot(30, 25)
      snapshot(59, 25)
      snapshot(60, 8_000)
      snapshot(-1, 9_000)

      get authenticated_root_path

      expect(response.body).to include("200", "+300.0%", "vs prev 30d")
      expect(response.body).not_to include("9,225")
    end
  end

  it "explains expired Apple agreements without directing users to replace keys" do
    create(:app_store_connect_credential, organization: organization, last_sync_status: "error",
      last_synced_at: Time.current, last_sync_error: "HTTP 403: A required agreement is missing or has expired")

    get authenticated_root_path

    expect(response.body).to include("Account Holder", "agreement")
    expect(response.body).not_to include("Your credentials look invalid or expired")
  end
end
