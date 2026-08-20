require "rails_helper"

RSpec.describe "Api::V1::ScreenshotProjects", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let!(:token_record) { ApiToken.generate_for(user: user, organization: organization, name: "Test Token", scopes: [ "read", "write" ]) }
  let(:api_token) { token_record[1] }

  let(:headers) do
    {
      "Authorization" => "Bearer #{api_token}",
      "Content-Type" => "application/json"
    }
  end

  let!(:project) do
    ScreenshotProject.create!(
      organization: organization,
      name: "My App Screenshots",
      platform: "both"
    )
  end

  describe "GET /api/v1/organizations/:organization_id/screenshot_projects" do
    it "returns list of projects" do
      get "/api/v1/organizations/#{organization.id}/screenshot_projects", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"]["projects"].length).to eq(1)
      expect(json["data"]["projects"].first["name"]).to eq("My App Screenshots")
    end

    it "requires authentication" do
      get "/api/v1/organizations/#{organization.id}/screenshot_projects"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/organizations/:organization_id/screenshot_projects/:id" do
    it "returns project details with scenes" do
      project.screenshot_scenes.create!(position: 1, caption_text: "Scene 1", source_image_data: "data")

      get "/api/v1/organizations/#{organization.id}/screenshot_projects/#{project.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"]["name"]).to eq("My App Screenshots")
      expect(json["data"]["scenes"].length).to eq(1)
    end

    it "returns 404 for non-existent project" do
      get "/api/v1/organizations/#{organization.id}/screenshot_projects/0", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
