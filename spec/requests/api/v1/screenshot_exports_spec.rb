require "rails_helper"

RSpec.describe "Api::V1::ScreenshotExports", type: :request do
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
  let!(:scene) do
    project.screenshot_scenes.create!(
      position: 1,
      source_image_data: "fake_png",
      source_image_content_type: "image/png",
      source_image_filename: "scene.png",
      caption_text: "Scene 1"
    )
  end

  let(:base_path) { "/api/v1/organizations/#{organization.id}/screenshot_projects/#{project.id}/screenshot_exports" }

  describe "POST create" do
    let(:valid_png_data) { Base64.encode64("\x89PNG\r\n\x1A\n".b + ("x" * 100).b) }

    it "stores a base64 PNG" do
      image_data = Base64.encode64("\x89PNG\r\n\x1A\n".b + ("x" * 100).b)

      post base_path, params: {
        width: 1320,
        height: 2868,
        scene_position: 1,
        image_data: image_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["data"]["resolution"]).to eq("1320x2868")
      expect(json["data"]["scene_position"]).to eq(1)

      file_path = project.exports_directory.join("1320x2868", "screenshot_01.png")
      expect(File.exist?(file_path)).to be true
    end

    it "rejects invalid width" do
      post base_path, params: { width: 0, height: 100, scene_position: 1, image_data: "abc" }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects missing image data" do
      post base_path, params: { width: 100, height: 100, scene_position: 1 }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects invalid position (0)" do
      post base_path, params: {
        width: 100, height: 100, scene_position: 0, image_data: valid_png_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("position")
    end

    it "rejects invalid position (100)" do
      post base_path, params: {
        width: 100, height: 100, scene_position: 100, image_data: valid_png_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("position")
    end

    it "rejects valid base64 but non-PNG content" do
      non_png_data = Base64.encode64("This is not a PNG file at all")

      post base_path, params: {
        width: 100, height: 100, scene_position: 1, image_data: non_png_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("not a valid PNG")
    end

    it "rejects image data exceeding 15MB" do
      large_png = "\x89PNG\r\n\x1A\n".b + ("\x00" * (16.megabytes)).b
      large_data = Base64.encode64(large_png)

      post base_path, params: {
        width: 100, height: 100, scene_position: 1, image_data: large_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("too large")
    end

    it "rejects oversized encoded payloads before decoding" do
      oversized_data = "A" * (Api::V1::ScreenshotExportsController::MAX_ENCODED_IMAGE_DATA_SIZE + 1)
      allow(Base64).to receive(:decode64).and_call_original

      post base_path, params: {
        width: 100,
        height: 100,
        scene_position: 1,
        image_data: oversized_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("Encoded image data too large")
      expect(Base64).not_to have_received(:decode64)
    end

    it "rejects when org export quota is exceeded" do
      allow_any_instance_of(ScreenshotProject).to receive(:org_within_export_quota?).and_return(false)

      post base_path, params: {
        width: 100, height: 100, scene_position: 1, image_data: valid_png_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("quota_exhausted")
      expect(json["message"]).to include("quota")
      expect(json["current_plan"]).to eq("pro")
      expect(json["next_plan"]).to eq("team")
      expect(json["suggestion"]).to include("Upgrade from Pro to Team")
    end

    it "uses fresh org export usage instead of stale cached totals" do
      other_project = ScreenshotProject.create!(
        organization: organization,
        name: "Other Project",
        platform: "both"
      )
      other_project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "other",
        source_image_content_type: "image/png",
        caption_text: "Other scene"
      )
      other_dir = other_project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(other_dir)
      File.binwrite(other_dir.join("screenshot_01.png"), "x" * 200)

      Rails.cache.write("org_export_storage:#{organization.id}", 0)
      allow_any_instance_of(ScreenshotProject).to receive(:max_export_storage_bytes_per_organization).and_return(250)

      post base_path, params: {
        width: 1320,
        height: 2868,
        scene_position: 1,
        image_data: valid_png_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("quota")
    ensure
      FileUtils.rm_rf(other_project.exports_directory) if defined?(other_project) && other_project.exports_directory.exist?
    end

    it "creates a ScreenshotExport record in the database" do
      image_data = Base64.encode64("\x89PNG\r\n\x1A\n".b + ("x" * 100).b)

      expect {
        post base_path, params: {
          width: 1320,
          height: 2868,
          scene_position: 1,
          image_data: image_data
        }.to_json, headers: headers
      }.to change(ScreenshotExport, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["data"]["storage"]).to eq("cloud")

      export = ScreenshotExport.last
      expect(export.resolution).to eq("1320x2868")
      expect(export.scene_position).to eq(1)
      expect(export.export_format).to eq("standard")
      expect(export.image).to be_attached
    end

    it "creates a ScreenshotExport with fastlane export_format" do
      image_data = Base64.encode64("\x89PNG\r\n\x1A\n".b + ("x" * 100).b)

      post base_path, params: {
        width: 1320,
        height: 2868,
        scene_position: 1,
        image_data: image_data,
        export_format: "fastlane"
      }.to_json, headers: headers

      expect(response).to have_http_status(:created)
      export = ScreenshotExport.last
      expect(export.export_format).to eq("fastlane")
    end

    it "upserts (overwrites) an existing cloud export for the same key" do
      image_data = Base64.encode64("\x89PNG\r\n\x1A\n".b + ("x" * 100).b)

      post base_path, params: {
        width: 1320, height: 2868, scene_position: 1, image_data: image_data
      }.to_json, headers: headers
      expect(response).to have_http_status(:created)

      expect {
        post base_path, params: {
          width: 1320, height: 2868, scene_position: 1, image_data: image_data
        }.to_json, headers: headers
      }.not_to change(ScreenshotExport, :count)

      expect(response).to have_http_status(:created)
    end

    it "blocks free plans from server-side screenshot staging" do
      user.update!(plan_tier: :free)

      post base_path, params: {
        width: 1320,
        height: 2868,
        scene_position: scene.position,
        image_data: valid_png_data
      }.to_json, headers: headers

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("plan_upgrade_required")
      expect(json["required_plan"]).to eq("pro")
      expect(json["current_plan"]).to eq("free")
    end
  end

  describe "GET index" do
    it "lists available exports" do
      dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "fake_png")

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"]["exports"].length).to eq(1)
      expect(json["data"]["exports"].first["resolution"]).to eq("1320x2868")
    end

    it "returns empty list when no exports exist" do
      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"]["exports"]).to eq([])
    end

    it "returns storage: cloud when cloud exports exist" do
      image_data = "\x89PNG\r\n\x1A\n".b + ("x" * 100).b
      ScreenshotExport.upsert_export!(
        project: project,
        resolution: "1320x2868",
        scene_position: 1,
        image_data: image_data
      )

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      exports = json["data"]["exports"]
      expect(exports.length).to eq(1)
      expect(exports.first["storage"]).to eq("cloud")
      expect(exports.first["resolution"]).to eq("1320x2868")
      expect(exports.first["scene_position"]).to eq(1)
      expect(exports.first["export_format"]).to eq("standard")
    end

    it "prefers cloud exports over local filesystem when both exist" do
      # Create a cloud export
      image_data = "\x89PNG\r\n\x1A\n".b + ("x" * 100).b
      ScreenshotExport.upsert_export!(
        project: project,
        resolution: "1320x2868",
        scene_position: 1,
        image_data: image_data
      )

      # Also create a local file
      dir = project.exports_directory.join("1080x1920")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "fake_png")

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      exports = json["data"]["exports"]
      # Should only return cloud exports since they exist
      expect(exports.all? { |e| e["storage"] == "cloud" }).to be true
    end

    it "blocks free plans from listing staged exports" do
      dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "fake_png")
      user.update!(plan_tier: :free)

      get base_path, headers: headers

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("plan_upgrade_required")
      expect(json["required_plan"]).to eq("pro")
      expect(json["current_plan"]).to eq("free")
    end
  end

  describe "GET download" do
    it "returns a zip file when exports exist" do
      dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "\x89PNG\r\n\x1A\n".b + ("x" * 50).b)

      # send_file + ensure { temp.unlink } doesn't work in integration tests
      # because the file is deleted before the response body is read.
      # Stub send_file to use send_data instead.
      allow_any_instance_of(Api::V1::ScreenshotExportsController).to receive(:send_file) do |controller, path, **opts|
        data = File.binread(path)
        controller.send(:send_data, data, type: opts[:type], disposition: opts[:disposition], filename: opts[:filename])
      end

      get "#{base_path}/download", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/zip")
      expect(response.headers["Content-Disposition"]).to include("screenshots.zip")
    end

    it "returns 404 when no exports directory exists" do
      get "#{base_path}/download", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "filters exports by preset" do
      ios_dir = project.exports_directory.join("1320x2868")
      android_dir = project.exports_directory.join("1080x1920")
      FileUtils.mkdir_p(ios_dir)
      FileUtils.mkdir_p(android_dir)
      File.binwrite(ios_dir.join("screenshot_01.png"), "\x89PNG".b + ("x" * 50).b)
      File.binwrite(android_dir.join("screenshot_01.png"), "\x89PNG".b + ("x" * 50).b)

      allow_any_instance_of(Api::V1::ScreenshotExportsController).to receive(:send_file) do |controller, path, **opts|
        data = File.binread(path)
        controller.send(:send_data, data, type: opts[:type], disposition: opts[:disposition], filename: opts[:filename])
      end

      get "#{base_path}/download", params: { preset: "android_phone" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/zip")
    end

    it "returns a fastlane-structured zip when fastlane=true" do
      dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "\x89PNG\r\n\x1A\n".b + ("x" * 50).b)

      allow_any_instance_of(Api::V1::ScreenshotExportsController).to receive(:send_file) do |controller, path, **opts|
        data = File.binread(path)
        controller.send(:send_data, data, type: opts[:type], disposition: opts[:disposition], filename: opts[:filename])
      end

      get "#{base_path}/download", params: { fastlane: "true" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/zip")
      expect(response.headers["Content-Disposition"]).to include("fastlane_screenshots.zip")
    end

    it "downloads cloud exports when available" do
      image_data = "\x89PNG\r\n\x1A\n".b + ("x" * 100).b
      ScreenshotExport.upsert_export!(
        project: project,
        resolution: "1320x2868",
        scene_position: 1,
        image_data: image_data
      )

      allow_any_instance_of(Api::V1::ScreenshotExportsController).to receive(:send_file) do |controller, path, **opts|
        data = File.binread(path)
        controller.send(:send_data, data, type: opts[:type], disposition: opts[:disposition], filename: opts[:filename])
      end

      get "#{base_path}/download", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/zip")
    end

    it "blocks free plans from downloading staged exports" do
      dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "\x89PNG\r\n\x1A\n".b + ("x" * 50).b)
      user.update!(plan_tier: :free)

      get "#{base_path}/download", headers: headers

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("plan_upgrade_required")
      expect(json["required_plan"]).to eq("pro")
      expect(json["current_plan"]).to eq("free")
    end
  end

  describe "DELETE destroy" do
    it "removes all export files" do
      dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "fake_png")

      delete base_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(Dir.exist?(project.exports_directory)).to be false
    end

    it "still allows export cleanup after a quota rejection" do
      allow_any_instance_of(ScreenshotProject).to receive(:org_within_export_quota?).and_return(false)

      post base_path, params: {
        width: 100, height: 100, scene_position: 1, image_data: Base64.encode64("\x89PNG\r\n\x1A\n".b + ("x" * 100).b)
      }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)

      dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "fake_png")

      delete base_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(Dir.exist?(project.exports_directory)).to be false
    end
  end

  after do
    FileUtils.rm_rf(project.exports_directory) if project.exports_directory.exist?
  end
end
