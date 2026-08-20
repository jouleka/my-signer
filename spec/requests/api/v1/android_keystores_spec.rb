require "rails_helper"

RSpec.describe "Api::V1::AndroidKeystores", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }

  let!(:admin_token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Admin Token", scopes: [ "read", "write", "admin" ]) }
  let(:admin_api_token) { admin_token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "X-User-Email"  => user.email,
      "Content-Type"  => "application/json"
    }
  end

  let(:admin_headers) do
    {
      "Authorization" => "Bearer #{admin_api_token}",
      "X-User-Email"  => user.email,
      "Content-Type"  => "application/json"
    }
  end

  before do
    validator = instance_double("Android::KeystoreValidator")
    result = instance_double("Android::KeystoreValidator::Result",
      valid_until: 1.year.from_now,
      alias: "alias",
      certificate_subject: "CN=Test",
      certificate_issuer: "CN=Test",
      valid_from: Time.current,
      fingerprints: {}
    )
    allow(validator).to receive(:validate!).and_return(result)
    allow(Android::KeystoreValidator).to receive(:new).and_return(validator)
  end

  def b64(data)
    Base64.strict_encode64(data)
  end

  describe "POST /api/v1/organizations/:organization_id/android_keystores" do
    it "creates a keystore and can activate exclusively" do
      # Pre-existing active keystore
      pre = organization.android_keystores.create!(name: "Old", keystore_file: "X", keystore_password: "pw", key_alias: "a", key_password: "kp", active: true)

      params = {
        android_keystore: {
          name: "NewKS",
          keystore_file_base64: b64("BINARYDATA"),
          keystore_password: "pw",
          key_alias: "alias",
          key_password: "kp",
          active: true
        }
      }

      expect {
        post "/api/v1/organizations/#{organization.id}/android_keystores",
             params: params.to_json,
             headers: headers
      }.to change(AndroidKeystore, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(organization.android_keystores.where(active: true).count).to eq(1)
    end

    # mysigner-49: create response uses keystore_json — assert the secrets
    # never round-trip back to the caller. The CLI must fetch them via the
    # dedicated /secrets endpoint instead.
    it "does not return keystore_password or key_password in the create response" do
      params = {
        android_keystore: {
          name: "ShapeKS",
          keystore_file_base64: b64("BINARYDATA"),
          keystore_password: "storepw",
          key_alias: "alias",
          key_password: "keypw"
        }
      }
      post "/api/v1/organizations/#{organization.id}/android_keystores",
           params: params.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json).not_to have_key("keystore_password")
      expect(json).not_to have_key("key_password")
    end

    it "emits an AuditEvent on create (mysigner-30)" do
      params = {
        android_keystore: {
          name: "AuditTestKS",
          keystore_file_base64: b64("BINARYDATA"),
          keystore_password: "pw",
          key_alias: "alias",
          key_password: "kp"
        }
      }

      expect {
        post "/api/v1/organizations/#{organization.id}/android_keystores",
             params: params.to_json,
             headers: headers
      }.to change(AuditEvent.where(organization: organization, action: "android_keystore_added"), :count).by(1)

      event = AuditEvent.where(organization: organization, action: "android_keystore_added").last
      expect(event.actor).to eq(user)
      expect(event.metadata).to include(
        "credential_id" => AndroidKeystore.last.id,
        "name"          => "AuditTestKS",
        "key_alias"     => "alias"
      )
    end
  end

  describe "GET /api/v1/organizations/:organization_id/android_keystores" do
    it "lists keystores and filters by android_app_id (includes org-wide keystores)" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "App")
      ks1 = organization.android_keystores.create!(name: "A", keystore_file: "X", keystore_password: "pw", key_alias: "a", key_password: "kp", android_app: app)
      ks2 = organization.android_keystores.create!(name: "B", keystore_file: "Y", keystore_password: "pw", key_alias: "a", key_password: "kp")

      get "/api/v1/organizations/#{organization.id}/android_keystores?android_app_id=#{app.id}", headers: headers
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      ids = json["android_keystores"].map { |k| k["id"] }
      # Filter includes app-specific AND org-wide keystores (android_app_id: nil)
      expect(ids).to match_array([ ks1.id, ks2.id ])
    end

    # mysigner-49: the index/list payload must never carry the plaintext
    # keystore_password or key_password. Secrets are only available through
    # the dedicated, audit-logged POST /android_keystores/:id/secrets endpoint.
    it "never includes keystore_password or key_password in the list payload" do
      organization.android_keystores.create!(name: "A", keystore_file: "X", keystore_password: "storepw", key_alias: "a", key_password: "keypw")

      get "/api/v1/organizations/#{organization.id}/android_keystores", headers: headers
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      json["android_keystores"].each do |ks|
        expect(ks).not_to have_key("keystore_password")
        expect(ks).not_to have_key("key_password")
      end
    end
  end

  describe "POST /api/v1/organizations/:organization_id/android_keystores/:id/activate" do
    it "activates exclusively within org/app scope" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "App")
      ks1 = organization.android_keystores.create!(name: "A", keystore_file: "X", keystore_password: "pw", key_alias: "a", key_password: "kp", android_app: app, active: true)
      ks2 = organization.android_keystores.create!(name: "B", keystore_file: "Y", keystore_password: "pw", key_alias: "a", key_password: "kp", android_app: app, active: false)

      post "/api/v1/organizations/#{organization.id}/android_keystores/#{ks2.id}/activate", headers: headers
      expect(response).to have_http_status(:ok)
      expect(organization.android_keystores.where(android_app_id: app.id, active: true).pluck(:id)).to eq([ ks2.id ])
    end

    # mysigner-49: the activate response also uses keystore_json. Same rule —
    # secrets are never returned inline; CLI must use /secrets.
    it "does not return keystore_password or key_password in the activate response" do
      ks = organization.android_keystores.create!(name: "ActivateShape", keystore_file: "X", keystore_password: "storepw", key_alias: "a", key_password: "keypw", active: false)
      post "/api/v1/organizations/#{organization.id}/android_keystores/#{ks.id}/activate", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).not_to have_key("keystore_password")
      expect(json).not_to have_key("key_password")
    end
  end

  describe "GET /api/v1/organizations/:organization_id/android_keystores/:id/download" do
    it "returns the keystore file with an admin-scoped token" do
      ks = organization.android_keystores.create!(name: "A", keystore_file: "XDATA", keystore_password: "pw", key_alias: "a", key_password: "kp")
      get "/api/v1/organizations/#{organization.id}/android_keystores/#{ks.id}/download", headers: admin_headers
      expect(response).to have_http_status(:success)
      expect(response.body).to eq("XDATA")
    end

    it "is 403 insufficient_scope for a non-admin token" do
      ks = organization.android_keystores.create!(name: "A", keystore_file: "XDATA", keystore_password: "pw", key_alias: "a", key_password: "kp")
      get "/api/v1/organizations/#{organization.id}/android_keystores/#{ks.id}/download", headers: headers
      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("insufficient_scope")
      expect(body["details"]["required_scope"]).to eq("admin")
    end
  end

  describe "DELETE /api/v1/organizations/:organization_id/android_keystores/:id" do
    it "deletes a keystore" do
      ks = organization.android_keystores.create!(name: "A", keystore_file: "X", keystore_password: "pw", key_alias: "a", key_password: "kp")
      expect {
        delete "/api/v1/organizations/#{organization.id}/android_keystores/#{ks.id}", headers: headers
      }.to change(AndroidKeystore, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /android_keystores/:id/download audit log" do
    it "emits an AuditEvent on download" do
      ks = organization.android_keystores.create!(name: "A", keystore_file: "XDATA", keystore_password: "pw", key_alias: "a", key_password: "kp")
      expect {
        get "/api/v1/organizations/#{organization.id}/android_keystores/#{ks.id}/download", headers: admin_headers
      }.to change(AuditEvent.where(action: "credential_read_android_keystore_file"), :count).by(1)
    end
  end
end
