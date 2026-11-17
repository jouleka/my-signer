require "rails_helper"
require "webmock/rspec"

RSpec.describe "Store connection permissions", type: :request do
  let(:owner) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: owner) }
  let(:member) { create(:user) }

  %i[app_store_connect google_play].each do |platform|
    %i[developer viewer].each do |role|
      it "prevents a #{role} from testing, activating or deleting #{platform} credentials" do
        create(:membership, organization: organization, user: member, role: role)
        credential = if platform == :app_store_connect
          create(:app_store_connect_credential, organization: organization, active: false)
        else
          create(:google_play_credential, organization: organization, active: false,
            service_account_json: {
              type: "service_account", project_id: "qa", private_key: "qa-only-key",
              client_email: "qa@example.test", client_id: "123"
            }.to_json)
        end
        sign_in member

        %i[test activate].each do |action|
          post public_send("#{action}_organization_#{platform}_credential_path", organization, credential)
          expect(response).to have_http_status(:redirect)
          expect(flash[:alert]).to be_present
          expect(credential.reload).not_to be_active
        end

        expect {
          delete public_send("organization_#{platform}_credential_path", organization, credential)
        }.not_to change(credential.class, :count)
        expect(flash[:alert]).to be_present
        expect(AppStoreConnectSyncJob).not_to have_been_enqueued
        expect(GooglePlaySyncJob).not_to have_been_enqueued
      end
    end
  end
end
