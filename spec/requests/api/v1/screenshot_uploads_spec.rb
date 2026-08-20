require "rails_helper"
require "fileutils"

RSpec.describe "Api::V1::ScreenshotUploads", type: :request do
  let!(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro) }
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

  let(:base_path) { "/api/v1/organizations/#{organization.id}/screenshot_uploads" }

  describe "POST /api/v1/organizations/:organization_id/screenshot_uploads" do
    before do
      Rails.cache.clear

      export_dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(export_dir)
      File.binwrite(export_dir.join("screenshot_01.png"), valid_png_bytes)
    end

    after { FileUtils.rm_rf(project.exports_directory) if project.exports_directory.exist? }

    it "creates an upload and enqueues job" do
      expect {
        post base_path, params: {
          project_id: project.id,
          target: "app_store_connect",
          config: { version_id: "v-123", locale: "en-US" }
        }.to_json, headers: headers
      }.to change(ScreenshotUpload, :count).by(1)
        .and have_enqueued_job(ScreenshotUploadJob)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["data"]["target"]).to eq("app_store_connect")
      expect(json["data"]["status"]).to eq("pending")
    end

    it "defaults locale from project default locale when omitted" do
      project.update!(locales: [ "fr-FR", "en-US" ])

      post base_path, params: {
        project_id: project.id,
        target: "app_store_connect",
        config: { version_id: "v-123" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      upload = ScreenshotUpload.order(:created_at).last
      expect(upload.config["locale"]).to eq("fr-FR")
    end

    it "rejects locale values not in project locales" do
      project.update!(locales: [ "en-US", "fr-FR" ])

      post base_path, params: {
        project_id: project.id,
        target: "app_store_connect",
        config: { version_id: "v-123", locale: "de-DE" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_request")
      expect(JSON.parse(response.body)["message"]).to include("project's locales")
    end

    it "rejects malformed locale values" do
      post base_path, params: {
        project_id: project.id,
        target: "app_store_connect",
        config: { version_id: "v-123", locale: "asdasdasd" }
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_request")
      expect(JSON.parse(response.body)["message"]).to include("Unsupported locale")
    end

    it "rejects invalid target" do
      post base_path, params: {
        project_id: project.id,
        target: "invalid",
        config: {}
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 404 for non-existent project" do
      post base_path, params: {
        project_id: 0,
        target: "app_store_connect",
        config: {}
      }.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 429 when rate limited" do
      allow(Rails.cache).to receive(:read).and_call_original
      allow(Rails.cache).to receive(:read).with(a_string_matching(/^api_screenshot_upload:/)).and_return(true)

      post base_path, params: {
        project_id: project.id,
        target: "app_store_connect",
        config: {}
      }.to_json, headers: headers

      expect(response).to have_http_status(:too_many_requests)
    end

    it "returns 409 when a pending upload exists for the same project and target" do
      ScreenshotUpload.create!(
        screenshot_project: project,
        organization: organization,
        target: "app_store_connect",
        status: "pending"
      )

      post base_path, params: {
        project_id: project.id,
        target: "app_store_connect",
        config: {}
      }.to_json, headers: headers

      expect(response).to have_http_status(:conflict)
    end

    it "counts uploads from other projects toward the org-wide daily limit" do
      other_project = ScreenshotProject.create!(
        organization: organization,
        name: "Other Project",
        platform: "both"
      )
      60.times do
        ScreenshotUpload.create!(
          screenshot_project: other_project,
          organization: organization,
          target: "app_store_connect",
          status: "completed"
        )
      end

      post base_path, params: {
        project_id: project.id,
        target: "app_store_connect",
        config: {}
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("quota_exhausted")
      expect(json["message"]).to include("Daily upload limit reached")
      expect(json["current_plan"]).to eq("pro")
      expect(json["next_plan"]).to eq("team")
      expect(json["suggestion"]).to include("Upgrade from Pro to Team")
    end

    it "blocks free plans from starting store uploads" do
      user.update!(plan_tier: :free)

      post base_path, params: {
        project_id: project.id,
        target: "app_store_connect",
        config: {}
      }.to_json, headers: headers

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("plan_upgrade_required")
      expect(json["required_plan"]).to eq("pro")
      expect(json["current_plan"]).to eq("free")
    end
  end

  describe "GET /api/v1/organizations/:organization_id/screenshot_uploads/:id" do
    it "returns upload status and progress" do
      upload = ScreenshotUpload.create!(
        screenshot_project: project,
        organization: organization,
        target: "app_store_connect",
        status: "in_progress",
        progress: { "completed" => 5, "total" => 10 }
      )

      get "#{base_path}/#{upload.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"]["status"]).to eq("in_progress")
      expect(json["data"]["progress"]["completed"]).to eq(5)
    end

    it "returns 404 for non-existent upload" do
      get "#{base_path}/0", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/organizations/:organization_id/screenshot_uploads" do
    it "returns recent uploads" do
      ScreenshotUpload.create!(
        screenshot_project: project,
        organization: organization,
        target: "app_store_connect"
      )
      ScreenshotUpload.create!(
        screenshot_project: project,
        organization: organization,
        target: "google_play"
      )

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"]["uploads"].length).to eq(2)
    end
  end

  private

  def valid_png_bytes
    "\x89PNG\r\n\x1A\n".b + ("\x00" * 100).b
  end
end
