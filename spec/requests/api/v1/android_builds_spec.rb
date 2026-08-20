require "rails_helper"

RSpec.describe "Api::V1::AndroidBuilds", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:android_app) { AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "Test App") }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "write" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "Content-Type" => "application/json"
    }
  end

  describe "POST /api/v1/organizations/:organization_id/android_apps/:android_app_id/android_builds" do
    let(:valid_params) do
      {
        android_build: {
          version_code: 42,
          version_name: "1.2.3",
          status: "completed"
        }
      }
    end

    it "creates a new build record" do
      expect {
        post "/api/v1/organizations/#{organization.id}/android_apps/#{android_app.id}/android_builds",
             params: valid_params.to_json,
             headers: headers
      }.to change(AndroidBuild, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["version_code"]).to eq(42)
      expect(json["version_name"]).to eq("1.2.3")
      expect(json["status"]).to eq("completed")
    end

    it "associates build with app and organization" do
      post "/api/v1/organizations/#{organization.id}/android_apps/#{android_app.id}/android_builds",
           params: valid_params.to_json,
           headers: headers

      build = AndroidBuild.last
      expect(build.android_app).to eq(android_app)
      expect(build.organization).to eq(organization)
    end

    it "returns error for duplicate version_code" do
      AndroidBuild.create!(
        organization: organization,
        android_app: android_app,
        version_code: 42,
        version_name: "1.0.0"
      )

      post "/api/v1/organizations/#{organization.id}/android_apps/#{android_app.id}/android_builds",
           params: valid_params.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("validation_failed")
    end

    context "with read-only token" do
      let!(:read_token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Read Token", scopes: [ "read" ]) }
      let(:read_api_token) { read_token_record[1] }

      let(:read_headers) do
        {
          "Authorization" => "Bearer #{read_api_token}",
          "Content-Type" => "application/json"
        }
      end

      it "rejects write operations" do
        post "/api/v1/organizations/#{organization.id}/android_apps/#{android_app.id}/android_builds",
             params: valid_params.to_json,
             headers: read_headers

        expect(response).to have_http_status(:forbidden)
      end
    end

    it "returns 404 for non-existent app" do
      post "/api/v1/organizations/#{organization.id}/android_apps/99999/android_builds",
           params: valid_params.to_json,
           headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
