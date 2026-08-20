require "rails_helper"

RSpec.describe "Asc Build Uploads API", type: :request do
  let(:user)   { create(:user) }
  let(:org)    { create(:organization, owner: user) }
  let(:token_pair) { ApiToken.generate_for(user: user, organization: org, name: "t", scopes: %w[read write admin]) }
  let(:plain_token) { token_pair.last }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}", "X-User-Email" => user.email, "Content-Type" => "application/json" } }
  let(:apple_app) { create(:apple_app, organization: org, app_store_id: "6757942957") }
  let!(:cred) { create(:app_store_connect_credential, organization: org) }

  describe "POST /builds/asc_upload" do
    let(:valid_body) do
      { apple_app_id: apple_app.id, cf_bundle_version: "1", cf_bundle_short_version_string: "1.0",
        platform: "IOS", file_name: "app.ipa", file_size: 100_000 }.to_json
    end

    before do
      allow_any_instance_of(AppStoreConnect::BuildUploadCreator).to receive(:call).and_return(
        build_upload: create(:asc_build_upload, organization: org, apple_app: apple_app, user: user),
        upload_operations: [ { method: "PUT", url: "https://x", offset: 0, length: 100_000, requestHeaders: [] } ]
      )
    end

    it "returns 201 with build_upload_id + upload_operations" do
      post "/api/v1/organizations/#{org.id}/builds/asc_upload", params: valid_body, headers: headers
      expect(response.status).to eq(201)
      body = JSON.parse(response.body)
      expect(body["build_upload_id"]).to be_an(Integer)
      expect(body["upload_operations"]).to be_an(Array)
    end

    it "emits an AuditEvent" do
      expect {
        post "/api/v1/organizations/#{org.id}/builds/asc_upload", params: valid_body, headers: headers
      }.to change(AuditEvent.where(action: "asc_build_upload_created"), :count).by(1)
    end

    context "when Apple returns a body containing credential material" do
      let(:leaky_body) do
        '{"errors":[{"title":"JWT invalid","detail":"Authorization: Bearer eyJhbGciOiJFUzI1NiIs.x.y"}]}'
      end

      before do
        allow_any_instance_of(AppStoreConnect::BuildUploadCreator).to receive(:call).and_raise(
          AppStoreConnect::BuildUploadCreator::AppleError.new(
            "ASC /v1/buildUploads returned 401; Bearer eyJhbGciOiJFUzI1NiIs.x.y",
            status: 401,
            apple_body: leaky_body
          )
        )
      end

      it "sanitizes bearer tokens and JWTs out of the rendered error" do
        post "/api/v1/organizations/#{org.id}/builds/asc_upload", params: valid_body, headers: headers
        expect(response.status).to eq(422)
        raw = response.body
        expect(raw).not_to include("eyJhbGciOiJFUzI1NiIs.x.y")
        expect(raw).to include("[REDACTED_JWT]").or include("Bearer [REDACTED]")
      end
    end
  end

  describe "PATCH /builds/asc_upload/:id" do
    let!(:upload) { create(:asc_build_upload, organization: org, apple_app: apple_app, user: user, state: "pending") }

    it "finalizes and returns 200" do
      allow_any_instance_of(AppStoreConnect::BuildUploadFinalizer).to receive(:call) do
        upload.update!(state: "uploaded", apple_state: "PROCESSING", uploaded_at: Time.current)
        upload
      end

      patch "/api/v1/organizations/#{org.id}/builds/asc_upload/#{upload.id}",
            params: { uploaded: true, source_file_checksums: { md5: "a", sha256: "b" } }.to_json,
            headers: headers
      expect(response.status).to eq(200)
      body = JSON.parse(response.body)
      expect(body["state"]).to eq("uploaded")
      expect(body["apple_state"]).to eq("PROCESSING")
    end
  end

  describe "GET /builds/asc_upload/:id" do
    let!(:upload) { create(:asc_build_upload, organization: org, apple_app: apple_app, user: user, state: "uploaded", apple_state: "PROCESSING") }

    before do
      allow_any_instance_of(AppStoreConnect::BuildUploadStatusChecker).to receive(:call) do
        upload.update!(apple_state: "COMPLETE")
        upload
      end
    end

    it "returns 200 with refreshed state" do
      get "/api/v1/organizations/#{org.id}/builds/asc_upload/#{upload.id}", headers: headers
      expect(response.status).to eq(200)
      body = JSON.parse(response.body)
      expect(body["apple_state"]).to eq("COMPLETE")
    end
  end
end
