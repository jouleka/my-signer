require "rails_helper"

RSpec.describe "Api::V1::Profiles auto_create", type: :request do
  let(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "X-User-Email" => user.email,
      "Content-Type" => "application/json"
    }
  end

  let(:credential) do
    AppStoreConnectCredential.create!(
      organization: organization,
      name: "Primary",
      key_id: "KEY12345",
      issuer_id: "11111111-1111-1111-1111-111111111111",
      private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
      team_id: "TEAM12345",
      active: true
    )
  end

  let(:bundle_id) do
    AppleBundleId.create!(
      organization: organization,
      remote_id: "bundle-remote-123",
      identifier: "com.example.app",
      name: "Example App"
    )
  end

  let(:certificate) do
    AppleCertificate.create!(
      organization: organization,
      remote_id: "cert-remote-123",
      name: "Distribution Cert",
      certificate_type: "IOS_DISTRIBUTION",
      status: "ACTIVE",
      expires_at: 1.year.from_now
    )
  end

  describe "POST /api/v1/organizations/:organization_id/profiles/auto_create" do
    before do
      credential
      bundle_id
      certificate
    end

    it "auto-creates an App Store profile successfully" do
      service_double = instance_double(AppStoreConnect::Profiles)
      allow(AppStoreConnect::Profiles).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:create).and_return({
        "data" => {
          "id" => "profile-remote-123",
          "attributes" => {
            "name" => "com.example.app App Store",
            "uuid" => "uuid-123",
            "profileType" => "IOS_APP_STORE",
            "profileState" => "ACTIVE",
            "platform" => "IOS",
            "expirationDate" => 1.year.from_now.iso8601
          }
        }
      })

      expect {
        post "/api/v1/organizations/#{organization.id}/profiles/auto_create",
             params: { bundle_id: "com.example.app", profile_type: "appstore" }.to_json,
             headers: headers
      }.to change(AppleProvisioningProfile, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["message"]).to eq("Profile created successfully")
      expect(json.dig("profile", "bundle_id_identifier")).to eq("com.example.app")
      expect(json.dig("profile", "profile_type")).to eq("IOS_APP_STORE")
      expect(json.dig("details", "certificates_used")).to eq(1)
      expect(json.dig("details", "devices_used")).to eq(0) # App Store profiles don't need devices
    end

    it "auto-creates a Development profile with devices" do
      dev_cert = AppleCertificate.create!(
        organization: organization,
        remote_id: "cert-dev-123",
        name: "Development Cert",
        certificate_type: "IOS_DEVELOPMENT",
        status: "ACTIVE",
        expires_at: 1.year.from_now
      )

      device = AppleDevice.create!(
        organization: organization,
        remote_id: "device-remote-123",
        name: "Test iPhone",
        udid: "00000000-0000000000000000",
        platform: "IOS",
        status: "ENABLED"
      )

      service_double = instance_double(AppStoreConnect::Profiles)
      allow(AppStoreConnect::Profiles).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:create).and_return({
        "data" => {
          "id" => "profile-dev-123",
          "attributes" => {
            "name" => "com.example.app Development",
            "uuid" => "uuid-dev-123",
            "profileType" => "IOS_APP_DEVELOPMENT",
            "profileState" => "ACTIVE",
            "platform" => "IOS",
            "expirationDate" => 1.year.from_now.iso8601
          }
        }
      })

      post "/api/v1/organizations/#{organization.id}/profiles/auto_create",
           params: { bundle_id: "com.example.app", profile_type: "development" }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json.dig("profile", "profile_type")).to eq("IOS_APP_DEVELOPMENT")
      expect(json.dig("details", "certificates_used")).to eq(1)
      expect(json.dig("details", "devices_used")).to eq(1)
    end

    it "returns error when bundle ID not found" do
      post "/api/v1/organizations/#{organization.id}/profiles/auto_create",
           params: { bundle_id: "com.unknown.app", profile_type: "appstore" }.to_json,
           headers: headers

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("not_found")
    end

    it "returns error when no valid certificates found" do
      certificate.update!(expires_at: 1.day.ago)

      post "/api/v1/organizations/#{organization.id}/profiles/auto_create",
           params: { bundle_id: "com.example.app", profile_type: "appstore" }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("precondition_failed")
    end

    it "returns error when no credentials configured" do
      credential.destroy

      post "/api/v1/organizations/#{organization.id}/profiles/auto_create",
           params: { bundle_id: "com.example.app", profile_type: "appstore" }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("credentials_required")
    end

    it "requires write scope" do
      token_record[0].update!(scopes: "read")

      post "/api/v1/organizations/#{organization.id}/profiles/auto_create",
           params: { bundle_id: "com.example.app", profile_type: "appstore" }.to_json,
           headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
