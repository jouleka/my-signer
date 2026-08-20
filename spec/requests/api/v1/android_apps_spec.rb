require "rails_helper"

RSpec.describe "Api::V1::AndroidApps", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "Content-Type" => "application/json"
    }
  end

  describe "GET /api/v1/organizations/:organization_id/android_apps" do
    it "lists apps with pagination and search" do
      AndroidApp.create!(organization: organization, package_name: "com.example.alpha", name: "Alpha")
      AndroidApp.create!(organization: organization, package_name: "com.example.beta", name: "Beta")

      get "/api/v1/organizations/#{organization.id}/android_apps?q=alpha", headers: headers

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["android_apps"].length).to eq(1)
      expect(json["android_apps"][0]["package_name"]).to eq("com.example.alpha")
      expect(json["pagination"]).to include("total" => 1)
    end
  end

  describe "GET /api/v1/organizations/:organization_id/android_apps/:id" do
    it "shows an app by id" do
      app = AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "App")

      get "/api/v1/organizations/#{organization.id}/android_apps/#{app.id}", headers: headers
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["package_name"]).to eq("com.example.app")
    end
  end

  describe "GET /api/v1/organizations/:organization_id/android_apps/package/:package_name" do
    it "shows an app by package name" do
      AndroidApp.create!(organization: organization, package_name: "com.example.pkg", name: "Pkg")

      get "/api/v1/organizations/#{organization.id}/android_apps/package/com.example.pkg", headers: headers
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["package_name"]).to eq("com.example.pkg")
    end

    it "returns 404 when not found" do
      get "/api/v1/organizations/#{organization.id}/android_apps/package/com.missing.pkg", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
