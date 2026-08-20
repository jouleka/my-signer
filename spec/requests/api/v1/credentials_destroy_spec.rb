require "rails_helper"

# mysigner-47 — bulk credential purge invoked by `mysigner logout --purge`.
# Verifies the WHY: a user-initiated logout-with-purge must irreversibly
# remove every signing credential the org holds and leave a per-row audit
# trail. The spec encodes intent on three axes:
#   1. authorization: only admin/owner with write scope can trigger
#   2. scope of deletion: all four credential kinds, exactly the org's rows
#   3. observability: one credential_destroyed_on_logout event per row,
#      created BEFORE the destroy so resource_id is captured
RSpec.describe "Api::V1::Credentials (mysigner-47 destroy)", type: :request do
  # plan_tier: :team raises the seat cap to 10 — the spec needs to add
  # admin/developer/viewer co-members to verify the Pundit policy gate.
  # (Free and Pro both cap at 1 seat; see Pricing::Entitlements.)
  let!(:user) do
    User.create!(email: "owner@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team)
  end
  let!(:organization) { Organization.create!(name: "Purge Org", owner: user) }
  let!(:token_record) do
    ApiToken.generate_for(user: user, organization: organization, name: "Logout Token", scopes: [ "read", "write" ])
  end
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "X-User-Email"  => user.email,
      "Content-Type"  => "application/json"
    }
  end

  # Build one row of each credential kind. The keystore is the only one with
  # real bytes (Vaulted needs SOMETHING in the envelope), but we sidestep
  # keytool validation by stubbing the model's pre-save validator — this
  # spec is about the purge contract, not keystore parsing.
  def seed_all_credentials!
    AppStoreConnectCredential.create!(
      organization: organization, name: "ASC1",
      key_id: "ABC12345", issuer_id: "11111111-1111-1111-1111-111111111111",
      team_id: "TEAM12", private_key: "pk", active: true
    )

    organization.create_apple_ads_credential!(
      client_id: "cid", team_id: "team", key_id: "kid",
      private_key_pem: OpenSSL::PKey::EC.generate("prime256v1").to_pem
    )

    GooglePlayCredential.create!(
      organization: organization, name: "GP1",
      service_account_json: {
        type: "service_account", project_id: "p",
        private_key: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
        client_email: "svc@example.com", client_id: "123"
      }.to_json,
      active: true
    )

    allow_any_instance_of(AndroidKeystore).to receive(:should_validate_with_keytool?).and_return(false)
    AndroidKeystore.create!(
      organization: organization, name: "KS1",
      keystore_file: "bytes", keystore_password: "pwd", key_alias: "alias", key_password: "pwd",
      active: true
    )
  end

  describe "DELETE /api/v1/organizations/:organization_id/credentials" do
    context "when caller is org owner with write scope" do
      it "purges every credential kind and returns per-kind counts" do
        seed_all_credentials!

        expect {
          delete "/api/v1/organizations/#{organization.id}/credentials", headers: headers
        }.to change(AppStoreConnectCredential, :count).by(-1)
          .and change(AppleAdsCredential, :count).by(-1)
          .and change(GooglePlayCredential, :count).by(-1)
          .and change(AndroidKeystore, :count).by(-1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["deleted"]).to eq(
          "asc" => 1, "apple_ads" => 1, "google_play" => 1, "android_keystore" => 1
        )
      end

      it "is idempotent: a second call on an empty org returns zero counts" do
        delete "/api/v1/organizations/#{organization.id}/credentials", headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["deleted"]).to eq(
          "asc" => 0, "apple_ads" => 0, "google_play" => 0, "android_keystore" => 0
        )
      end

      it "emits one credential_destroyed_on_logout AuditEvent per destroyed row" do
        seed_all_credentials!

        expect {
          delete "/api/v1/organizations/#{organization.id}/credentials", headers: headers
        }.to change {
          AuditEvent.where(organization: organization, action: "credential_destroyed_on_logout").count
        }.by(4)

        kinds = AuditEvent
          .where(organization: organization, action: "credential_destroyed_on_logout")
          .pluck(:metadata)
          .map { |m| m["kind"] }
        expect(kinds).to match_array(%w[asc apple_ads google_play android_keystore])
      end

      it "captures resource_id in the audit event by emitting BEFORE destroy" do
        seed_all_credentials!
        asc_id = AppStoreConnectCredential.last.id

        delete "/api/v1/organizations/#{organization.id}/credentials", headers: headers

        asc_event = AuditEvent.where(
          organization: organization,
          action: "credential_destroyed_on_logout"
        ).find { |e| e.metadata["kind"] == "asc" }

        expect(asc_event.resource_id).to eq(asc_id)
        expect(asc_event.resource_type).to eq("AppStoreConnectCredential")
        expect(asc_event.metadata["credential_id"]).to eq(asc_id)
        expect(asc_event.metadata["organization_id"]).to eq(organization.id)
      end

      it "does not touch credentials owned by other organizations" do
        seed_all_credentials!

        other_user = User.create!(email: "other@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
        other_org = Organization.create!(name: "Other Org", owner: other_user)
        other_cred = GooglePlayCredential.create!(
          organization: other_org, name: "Untouched",
          service_account_json: {
            type: "service_account", project_id: "p",
            private_key: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
            client_email: "svc@example.com", client_id: "123"
          }.to_json,
          active: true
        )

        delete "/api/v1/organizations/#{organization.id}/credentials", headers: headers

        expect(GooglePlayCredential.exists?(other_cred.id)).to be true
      end
    end

    context "authorization" do
      it "rejects a token without write scope" do
        token_record[0].update!(scopes: "read")

        delete "/api/v1/organizations/#{organization.id}/credentials", headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["error"]).to eq("insufficient_scope")
      end

      it "rejects developer-role members (manage_credentials? gate)" do
        developer = User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
        organization.memberships.create!(user: developer, role: :developer)
        dev_token = ApiToken.generate_for(user: developer, organization: organization, name: "Dev Token", scopes: [ "read", "write" ])

        delete "/api/v1/organizations/#{organization.id}/credentials",
               headers: {
                 "Authorization" => "Bearer #{dev_token[1]}",
                 "X-User-Email"  => developer.email,
                 "Content-Type"  => "application/json"
               }

        expect(response).to have_http_status(:forbidden)
      end

      it "rejects viewer-role members" do
        viewer = User.create!(email: "viewer@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
        organization.memberships.create!(user: viewer, role: :viewer)
        viewer_token = ApiToken.generate_for(user: viewer, organization: organization, name: "Viewer Token", scopes: [ "read", "write" ])

        delete "/api/v1/organizations/#{organization.id}/credentials",
               headers: {
                 "Authorization" => "Bearer #{viewer_token[1]}",
                 "X-User-Email"  => viewer.email,
                 "Content-Type"  => "application/json"
               }

        expect(response).to have_http_status(:forbidden)
      end

      it "accepts admin-role members (manage_credentials? permits admin)" do
        admin = User.create!(email: "admin@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
        organization.memberships.create!(user: admin, role: :admin)
        admin_token = ApiToken.generate_for(user: admin, organization: organization, name: "Admin Token", scopes: [ "read", "write" ])

        delete "/api/v1/organizations/#{organization.id}/credentials",
               headers: {
                 "Authorization" => "Bearer #{admin_token[1]}",
                 "X-User-Email"  => admin.email,
                 "Content-Type"  => "application/json"
               }

        expect(response).to have_http_status(:ok)
      end

      it "rejects a token whose org differs from the URL" do
        other_user = User.create!(email: "outsider@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
        other_org = Organization.create!(name: "Outsider Org", owner: other_user)
        outsider_token = ApiToken.generate_for(user: other_user, organization: other_org, name: "Outsider Token", scopes: [ "read", "write" ])

        delete "/api/v1/organizations/#{organization.id}/credentials",
               headers: {
                 "Authorization" => "Bearer #{outsider_token[1]}",
                 "X-User-Email"  => other_user.email,
                 "Content-Type"  => "application/json"
               }

        expect(response).to have_http_status(:forbidden)
      end

      it "requires X-User-Email header" do
        delete "/api/v1/organizations/#{organization.id}/credentials",
               headers: headers.except("X-User-Email")

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
