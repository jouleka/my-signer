require "rails_helper"
require "tmpdir"
require "zlib"

RSpec.describe "Screenshot locale uploads", type: :request do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:project) { create(:screenshot_project, organization: organization, locales: [ "en-US", "de-DE" ]) }
  let(:localized_images) do
    {
      "en-US" => png_image(1320, 2868, [ 20, 80, 180 ]),
      "de-DE" => png_image(1320, 2868, [ 180, 30, 60 ])
    }
  end

  before do
    sign_in user
    Rails.cache.clear
    @exports_root = Dir.mktmpdir("studio-exports-", Rails.root.join("tmp"))
    allow(ScreenshotProject).to receive(:exports_root).and_return(Pathname.new(@exports_root))
    project.screenshot_scenes.create!(position: 1, source_image_data: File.binread(Rails.root.join("spec/fixtures/files/studio_screen.png")))
  end

  after { FileUtils.remove_entry(@exports_root) if @exports_root }

  def png_image(width, height, color)
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    pixels = ("\x00".b + color.pack("C*") * width) * height
    "\x89PNG\r\n\x1a\n".b +
      chunk.call("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
      chunk.call("IDAT", Zlib::Deflate.deflate(pixels)) + chunk.call("IEND", "".b)
  end

  def image_digests(images)
    images.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) }
  end

  def stage_localized_exports
    post upload_export_organization_screenshot_project_path(organization, project), params: {
      screenshots: localized_images.map do |locale, bytes|
        { width: 1320, height: 2868, scene_position: 1, locale: locale, image_data: Base64.strict_encode64(bytes) }
      end
    }, as: :json
    expect(response).to have_http_status(:created)
  end

  def apple_screenshots
    create(:app_store_connect_credential, organization: organization)
    client = instance_double(AppStoreConnect::Client)
    versions = instance_double(AppStoreConnect::Versions)
    screenshots = instance_double(AppStoreConnect::Screenshots)
    allow(AppStoreConnect::Client).to receive(:new).and_return(client)
    allow(AppStoreConnect::Versions).to receive(:new).and_return(versions)
    allow(AppStoreConnect::Screenshots).to receive(:new).and_return(screenshots)
    allow(versions).to receive(:localizations).and_return(localized_images.keys.map do |locale|
      { "id" => locale, "attributes" => { "locale" => locale } }
    end)
    allow(screenshots).to receive(:list_screenshot_sets).and_return([])
    allow(screenshots).to receive(:create_screenshot_set) do |**attrs|
      { "data" => { "id" => attrs.fetch(:localization_id) } }
    end
    screenshots
  end

  def google_client
    create(:google_play_credential, organization: organization, service_account_json: {
      type: "service_account", project_id: "qa", private_key: "qa-only", client_email: "qa@example.test", client_id: "123"
    }.to_json)
    client = instance_double(GooglePlay::Client)
    service = instance_double(Google::Apis::AndroidpublisherV3::AndroidPublisherService)
    allow(GooglePlay::Client).to receive(:new).and_return(client)
    allow(client).to receive(:service).and_return(service)
    allow(client).to receive(:create_edit).and_return(Google::Apis::AndroidpublisherV3::AppEdit.new(id: "edit-1"))
    allow(client).to receive(:commit_edit)
    client
  end

  it "stores both rendered languages separately instead of discarding the second image" do
    stage_localized_exports

    expect(response.parsed_body.dig("data", "uploaded")).to eq(2)
    expect(project.screenshot_exports.pluck(:locale)).to contain_exactly("en-US", "de-DE")
    localized_images.each do |locale, bytes|
      actual = project.screenshot_exports.for_locale(locale).sole.image.download
      expect(Digest::SHA256.hexdigest(actual)).to eq(Digest::SHA256.hexdigest(bytes))
    end
  end

  it "replaces the prior export batch, including stale scenes and locales" do
    ScreenshotExport.upsert_export!(project: project, resolution: "1080x1920", scene_position: 2,
      locale: "fr-FR", image_data: localized_images.fetch("en-US"))
    stage_localized_exports

    expect(project.screenshot_exports.pluck(:scene_position, :locale)).to contain_exactly([ 1, "en-US" ], [ 1, "de-DE" ])
  end

  it "uploads the matching language image to each Apple localization" do
    screenshots = apple_screenshots
    sent = {}
    allow(screenshots).to receive(:upload_screenshot!) do |set_id:, file_path:|
      sent[set_id] = File.binread(file_path)
    end

    stage_localized_exports
    upload = create(:screenshot_upload, organization: organization, screenshot_project: project,
      target: "app_store_connect", config: { "version_id" => "version-1", "locales" => localized_images.keys })
    ScreenshotUploadJob.new.perform(upload.id)

    expect(upload.reload.status).to eq("completed")
    expect(image_digests(sent)).to eq(image_digests(localized_images))
  end

  it "uploads the matching language image to each Google Play listing" do
    client = google_client
    sent = {}
    allow(client.service).to receive(:upload_edit_image) do |_package, _edit, language, _type, upload_source:, content_type:|
      sent[language] = File.binread(upload_source)
    end

    android_images = {
      "en-US" => png_image(1080, 1920, [ 20, 80, 180 ]),
      "de-DE" => png_image(1080, 1920, [ 180, 30, 60 ])
    }
    post upload_export_organization_screenshot_project_path(organization, project), params: {
      screenshots: android_images.map do |locale, bytes|
        { width: 1080, height: 1920, scene_position: 1, locale: locale, image_data: Base64.strict_encode64(bytes) }
      end
    }, as: :json
    expect(response).to have_http_status(:created)
    upload = create(:screenshot_upload, organization: organization, screenshot_project: project,
      target: "google_play", config: { "package_name" => "com.example.qa", "locales" => localized_images.keys })
    ScreenshotUploadJob.new.perform(upload.id)

    expect(upload.reload.status).to eq("completed")
    expect(image_digests(sent)).to eq(image_digests(android_images))
  end

  it "does not upload a different language when a requested translation is missing" do
    screenshots = apple_screenshots
    stage_localized_exports
    project.screenshot_exports.for_locale("de-DE").destroy_all
    expect(screenshots).not_to receive(:create_screenshot_set)
    expect(screenshots).not_to receive(:upload_screenshot!)

    upload = create(:screenshot_upload, organization: organization, screenshot_project: project,
      target: "app_store_connect", config: { "version_id" => "version-1", "locales" => localized_images.keys })
    ScreenshotUploadJob.new.perform(upload.id)

    expect(upload.reload).to be_failed
    expect(upload.progress["errors"]).to include(a_string_including("No export files match"))
  end

  it "preserves numeric scene order and removes temporary downloads after uploading" do
    screenshots = apple_screenshots
    [ 10, 2, 1 ].each do |position|
      ScreenshotExport.upsert_export!(project: project, resolution: "1320x2868", scene_position: position,
        locale: "en-US", image_data: "scene #{position}")
    end
    sent = []
    temp_paths = []
    allow(screenshots).to receive(:upload_screenshot!) do |set_id:, file_path:|
      sent << File.binread(file_path)
      temp_paths << file_path
    end
    upload = create(:screenshot_upload, organization: organization, screenshot_project: project,
      target: "app_store_connect", config: { "version_id" => "version-1", "locale" => "en-US" })
    ScreenshotUploadJob.new.perform(upload.id)

    expect(upload.reload).to be_completed
    expect(sent).to eq([ "scene 1", "scene 2", "scene 10" ])
    expect(temp_paths).not_to be_empty
    expect(temp_paths.none? { |path| File.exist?(path) }).to be true
  end

  it "counts each image once when a Google Play upload fails partway through a group" do
    client = google_client
    2.times do |i|
      ScreenshotExport.upsert_export!(project: project, resolution: "1080x1920", scene_position: i + 1,
        locale: "en-US", image_data: localized_images.fetch("en-US"))
    end
    count = 0
    allow(client.service).to receive(:upload_edit_image) do
      count += 1
      raise Google::Apis::ClientError, "Image rejected" if count == 2
    end
    upload = create(:screenshot_upload, organization: organization, screenshot_project: project,
      target: "google_play", config: { "package_name" => "com.example.qa", "language" => "en-US" })
    ScreenshotUploadJob.new.perform(upload.id)

    expect(upload.reload).to be_failed
    expect(upload.progress).to include("completed" => 2, "total" => 2)
    expect(upload.progress["errors"]).to include(a_string_including("Image rejected"))
  end

  it "replaces a same-sized batch at the quota limit without double-counting storage" do
    bytes = localized_images.values.sum(&:bytesize)
    allow_any_instance_of(ScreenshotProject).to receive(:max_export_storage_bytes_per_organization).and_return(bytes)
    stage_localized_exports
    Rails.cache.clear
    stage_localized_exports

    expect(ScreenshotProject.org_export_storage_bytes(organization.id, use_cache: false)).to eq(bytes)
    expect(project.export_storage_bytes).to eq(0)
  end

  it "preserves the previous batch when any replacement image is invalid" do
    stage_localized_exports
    previous_ids = project.screenshot_exports.ids
    Rails.cache.clear
    post upload_export_organization_screenshot_project_path(organization, project), params: {
      screenshots: [
        { width: 1320, height: 2868, scene_position: 1, locale: "en-US", image_data: Base64.strict_encode64(localized_images.fetch("en-US")) },
        { width: 1320, height: 2868, scene_position: 1, locale: "de-DE", image_data: Base64.strict_encode64("broken image") }
      ]
    }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["message"]).to include("No exports were replaced")
    expect(project.screenshot_exports.ids).to match_array(previous_ids)
  end
end
