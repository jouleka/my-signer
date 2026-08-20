require "rails_helper"

RSpec.describe "AndroidKeystoresController", type: :request do
  let(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }

  before do
    sign_in user, scope: :user
  end

  describe "GET /organizations/:organization_id/android_keystores" do
    it "renders successfully" do
      get organization_android_keystores_path(organization)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /organizations/:organization_id/android_keystores" do
    it "creates a keystore when validation succeeds" do
      validator_result = instance_double(
        Android::KeystoreValidator::Result,
        valid_until: 1.year.from_now,
        alias: "release",
        certificate_subject: "CN=Demo",
        certificate_issuer: "CN=Demo",
        valid_from: Time.current,
        fingerprints: {}
      )
      validator = instance_double(Android::KeystoreValidator, validate!: validator_result)
      allow(Android::KeystoreValidator).to receive(:new).and_return(validator)

      file = Tempfile.new("keystore")
      file.write("dummy")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "application/octet-stream")

      expect {
        post organization_android_keystores_path(organization), params: {
          android_keystore: {
            name: "Release Key",
            keystore_file: upload,
            keystore_password: "storepass",
            key_password: "keypass",
            key_alias: "release",
            active: true
          }
        }
      }.to change(AndroidKeystore, :count).by(1)

      expect(response).to redirect_to(organization_android_keystores_path(organization))
      expect(Android::KeystoreValidator).to have_received(:new).at_least(:once)
    ensure
      file.close
      file.unlink
    end
  end

  describe "POST /organizations/:organization_id/android_keystores/validate" do
    it "returns metadata as JSON" do
      validator_result = instance_double(
        Android::KeystoreValidator::Result,
        valid_until: Time.current,
        valid_from: Time.current,
        alias: "release",
        certificate_subject: "CN=Demo",
        certificate_issuer: "CN=Demo",
        fingerprints: { sha1: "AA" }
      )
      validator = instance_double(Android::KeystoreValidator, validate!: validator_result)
      allow(Android::KeystoreValidator).to receive(:new).and_return(validator)

      file = Tempfile.new("keystore")
      file.write("dummy")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "application/octet-stream")

      post validate_organization_android_keystores_path(organization), params: {
        android_keystore: {
          keystore_file: upload,
          keystore_password: "storepass",
          key_password: "keypass",
          key_alias: "release"
        }
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["valid"]).to eq(true)
      expect(body["alias"]).to eq("release")
    ensure
      file.close
      file.unlink
    end
  end
end
