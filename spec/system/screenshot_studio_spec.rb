require "rails_helper"
require "zip"
require "tmpdir"

RSpec.describe "Screenshot Studio", type: :system, js: true do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:source_image_path) { Rails.root.join("spec/fixtures/files/studio_screen.png") }

  before do
    user.update!(last_organization: organization)
    sign_in user
    @downloads = Dir.mktmpdir("studio-downloads-", Rails.root.join("tmp"))
    @exports_root = Dir.mktmpdir("studio-exports-", Rails.root.join("tmp"))
    allow(ScreenshotProject).to receive(:exports_root).and_return(Pathname.new(@exports_root))
    page.driver.browser.execute_cdp("Page.setDownloadBehavior", behavior: "allow", downloadPath: @downloads)
  end

  after do
    FileUtils.remove_entry(@downloads) if @downloads
    FileUtils.remove_entry(@exports_root) if @exports_root
  end

  def create_project_with_scene(locales: [])
    project = create(:screenshot_project, organization: organization,
      settings: ScreenshotProject::DEFAULT_CUSTOM_SETTINGS, locales: locales)
    scene = project.screenshot_scenes.new(caption_text: "Original caption")
    File.open(source_image_path) do |file|
      scene.source_image.attach(io: file, filename: "studio_screen.png", content_type: "image/png")
      scene.save!
    end
    [ project, scene ]
  end

  def expect_preview_ready
    expect(page).to have_css('[data-screenshot-editor-target="previewSize"]', text: /\d+x\d+/, wait: 15)
  end

  def downloaded_pngs(filename)
    downloaded_images(filename).transform_values { |png| png[16, 8].unpack("NN") }
  end

  def downloaded_images(filename)
    path = File.join(@downloads, filename)
    Timeout.timeout(30) { sleep 0.1 until File.exist?(path) && Dir.glob("#{@downloads}/*.crdownload").empty? }
    Zip::File.open(path) do |zip|
      zip.reject(&:directory?).to_h do |entry|
        png = entry.get_input_stream.read
        expect(png[0, 8]).to eq("\x89PNG\r\n\x1A\n".b)
        [ entry.name, png ]
      end
    end
  end

  def corner_pixel(png)
    page.evaluate_async_script(<<~JS, Base64.strict_encode64(png))
      const [base64, done] = arguments;
      const image = new Image();
      image.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = 1;
        const context = canvas.getContext("2d");
        context.drawImage(image, 0, 0);
        done(Array.from(context.getImageData(0, 0, 1, 1).data));
      };
      image.src = "data:image/png;base64," + base64;
    JS
  end

  it "creates a project, initializes its first uploaded scene, and saves captions through a reload" do
    visit new_organization_screenshot_project_path(organization)
    fill_in "e.g. MyApp v2.0 Screenshots", with: "Browser-created project"
    click_button "Create Project"
    expect(page).to have_content("No Scenes Yet")

    attach_file "screenshot_scene[files][]", source_image_path, make_visible: true
    expect(page).to have_content("Screenshot uploaded")
    expect_preview_ready
    fill_in "Title text...", with: "A persisted title"
    fill_in "Subtitle text...", with: "A persisted subtitle"
    find('[data-screenshot-editor-target="saveButton"]').click
    expect(page).to have_css('[data-screenshot-editor-target="saveLabel"]', text: "Saved")

    page.refresh
    expect_preview_ready
    expect(page).to have_field("Title text...", with: "A persisted title")
    expect(page).to have_field("Subtitle text...", with: "A persisted subtitle")
    expect(organization.screenshot_projects.sole.screenshot_scenes.sole.caption_text).to eq("A persisted title")
  end

  [ false, true ].each do |fastlane|
    it "exports every selected resolution without overwriting files#{' in Fastlane layout' if fastlane}" do
      project, = create_project_with_scene
      visit editor_organization_screenshot_project_path(organization, project)
      expect_preview_ready
      find('[data-action="click->screenshot-export#openModal"]').click
      within("#export_modal") do
        find('[data-preset="ios_ipad"]').check
        find('[data-screenshot-export-target="fastlaneToggle"]').check if fastlane
        click_button "Export ZIP"
      end

      pngs = downloaded_pngs(fastlane ? "fastlane_screenshots.zip" : "screenshots.zip")
      expect(pngs.values).to contain_exactly(
        [ 1320, 2868 ], [ 1290, 2796 ], [ 1242, 2688 ],
        [ 2048, 2732 ], [ 1668, 2388 ], [ 1080, 1920 ]
      )
    end
  end

  it "saves edits to both scenes when Save is clicked after switching scenes" do
    project, first = create_project_with_scene
    second = first.copy_to_project(project)
    visit editor_organization_screenshot_project_path(organization, project)
    expect_preview_ready

    fill_in "Title text...", with: "First edited title"
    find("[data-screenshot-editor-target='thumbnail'][data-screenshot-editor-scene-id-param='#{second.id}']").click
    fill_in "Title text...", with: "Second edited title"
    find('[data-screenshot-editor-target="saveButton"]').click
    expect(page).to have_css('[data-screenshot-editor-target="saveLabel"]', text: "Saved")

    page.refresh
    expect_preview_ready
    expect(page).to have_field("Title text...", with: "First edited title")
    find("[data-screenshot-editor-target='thumbnail'][data-screenshot-editor-scene-id-param='#{second.id}']").click
    expect(page).to have_field("Title text...", with: "Second edited title")
    expect(first.reload.caption_text).to eq("First edited title")
    expect(second.reload.caption_text).to eq("Second edited title")
  end

  it "keeps a selected scene's background out of other scenes in the downloaded images" do
    project, first = create_project_with_scene
    first.copy_to_project(project)
    first.update!(overrides: { background_type: "solid", background_color: "#ff0000" })
    project.update!(settings: project.settings.merge("background_type" => "solid", "background_color" => "#000000"))
    visit editor_organization_screenshot_project_path(organization, project)
    expect_preview_ready
    find('[data-action="click->screenshot-export#openModal"]').click
    within("#export_modal") do
      find('[data-preset="ios_required"]').uncheck
      click_button "Export ZIP"
    end

    images = downloaded_images("screenshots.zip")
    expect(images.size).to eq(2)
    expect(corner_pixel(images.find { |name, _| name.include?("screenshot_01_") }.last)).to eq([ 255, 0, 0, 255 ])
    expect(corner_pixel(images.find { |name, _| name.include?("screenshot_02_") }.last)).to eq([ 0, 0, 0, 255 ])
  end

  it "saves separate locale captions and keeps the draft after a failed save" do
    project, scene = create_project_with_scene(locales: [ "en-US", "de-DE" ])
    visit editor_organization_screenshot_project_path(organization, project)
    expect_preview_ready
    fill_in "Title text...", with: "English title"
    find('[data-screenshot-editor-target="localeBar"] [data-locale="de-DE"]').click
    fill_in "Title text...", with: "Deutscher Titel"
    fill_in "Subtitle text...", with: "Deutscher Untertitel"

    page.driver.browser.execute_cdp("Network.enable")
    page.driver.browser.execute_cdp("Network.setBlockedURLs", urls: [ "*screenshot_scenes/#{scene.id}" ])
    find('[data-screenshot-editor-target="saveButton"]').click
    expect(page).to have_css('[data-screenshot-editor-target="saveLabel"]', text: "Failed to save")
    expect(page).to have_field("Title text...", with: "Deutscher Titel")
    expect(scene.reload.caption_text).to eq("Original caption")

    page.driver.browser.execute_cdp("Network.setBlockedURLs", urls: [])
    find_field("Title text...").send_keys([ :control, "s" ])
    expect(page).to have_css('[data-screenshot-editor-target="saveLabel"]', text: "Saved")
    page.refresh
    expect_preview_ready
    expect(page).to have_field("Title text...", with: "English title")
    find('[data-screenshot-editor-target="localeBar"] [data-locale="de-DE"]').click
    expect(page).to have_field("Title text...", with: "Deutscher Titel")
    expect(page).to have_field("Subtitle text...", with: "Deutscher Untertitel")
  ensure
    page.driver.browser.execute_cdp("Network.setBlockedURLs", urls: [])
  end

  it "applies a template, undoes and redoes it, then saves it through a reload" do
    project, scene = create_project_with_scene
    visit editor_organization_screenshot_project_path(organization, project)
    expect_preview_ready
    find("summary", text: "Templates").click
    template = first("[data-template-key]")
    caption = JSON.parse(template["data-template-settings"]).fetch("caption_text")
    template.click
    expect(page).to have_field("Title text...", with: caption)
    find('[data-screenshot-editor-target="undoButton"]').click
    expect(page).to have_field("Title text...", with: "Original caption")
    find('[data-screenshot-editor-target="redoButton"]').click
    expect(page).to have_field("Title text...", with: caption)
    find('[data-screenshot-editor-target="saveButton"]').click
    expect(page).to have_css('[data-screenshot-editor-target="saveLabel"]', text: "Saved")
    page.refresh
    expect_preview_ready
    expect(page).to have_field("Title text...", with: caption)
    expect(scene.reload.overrides).to be_present
  end

  it "stages translated Google Play images with the selected replacement option and shows a job failure" do
    project, scene = create_project_with_scene(locales: [ "en-US", "de-DE" ])
    scene.copy_to_project(project)
    scene.update!(overrides: { background_color: "#ff0000" },
      locale_variants: { "de-DE" => { "caption_text" => "Deutscher Titel" } })
    create(:google_play_credential, organization: organization, service_account_json: {
      type: "service_account", project_id: "qa", private_key: "qa-only", client_email: "qa@example.test", client_id: "123"
    }.to_json)
    # Both store tabs are present: their independent replace toggles must not
    # read the first (Apple) checkbox when uploading to Google Play.
    create(:app_store_connect_credential, organization: organization)
    visit editor_organization_screenshot_project_path(organization, project)
    expect_preview_ready
    find('[data-action="click->screenshot-store-upload#openModal"]').click
    within("#store_upload_modal") do
      click_button "Google Play", exact: false
      fill_in "com.example.app", with: "com.example.qa"
      check "Upload all locales (2)"
      check "Replace existing screenshots"
      click_button "Upload to Google Play"
      expect(page).to have_content("Starting store upload", wait: 20)
    end
    Timeout.timeout(10) { sleep 0.1 until project.screenshot_uploads.exists? }
    upload = project.screenshot_uploads.sole
    expect(upload.config).to include("locales" => [ "en-US", "de-DE" ], "replace_existing" => true)
    exports = project.screenshot_exports
    expect(exports.count).to eq(4)
    exports.each do |export|
      expected = export.scene_position == 1 ? [ 255, 0, 0, 255 ] : [ 0, 0, 0, 255 ]
      expect(corner_pixel(export.image.download)).to eq(expected)
    end
    expect(exports.where(scene_position: 1).map { |export| export.image.blob.checksum }.uniq.size).to eq(2)

    upload.mark_failed!("Google Play rejected the screenshot")
    within("#store_upload_modal") do
      expect(page).to have_content("Upload failed: Google Play rejected the screenshot", wait: 10)
      expect(page).to have_button("Upload to Google Play", disabled: false)
      click_button "Upload to Google Play"
      expect(page).to have_content("Starting store upload", wait: 20)
      expect(page).to have_css('[data-screenshot-store-upload-target="progressBar"]', visible: true)
    end
    Timeout.timeout(10) { sleep 0.1 until project.screenshot_uploads.count == 2 }
    project.screenshot_uploads.order(:id).last.mark_completed!
    expect(page).to have_content("Upload completed successfully!", wait: 10)
  end

  it "keeps the complete preview visible with its original aspect ratio on mobile and desktop" do
    project, = create_project_with_scene
    page.current_window.resize_to(390, 844)
    visit editor_organization_screenshot_project_path(organization, project)
    expect_preview_ready

    [ [ 390, 844 ], [ 1400, 900 ] ].each do |width, height|
      page.current_window.resize_to(width, height)
      bounds = page.evaluate_script(<<~JS)
        (() => {
          const canvas = document.querySelector('[data-screenshot-editor-target="canvas"]');
          const container = document.querySelector('[data-screenshot-editor-target="canvasContainer"]');
          const painted = canvas.getBoundingClientRect();
          const parent = container.getBoundingClientRect();
          return { right: painted.right, containerRight: parent.right, viewport: innerWidth,
            aspect: painted.width / painted.height, imageAspect: canvas.width / canvas.height };
        })()
      JS
      expect(bounds["right"]).to be <= bounds["containerRight"]
      expect(bounds["right"]).to be <= bounds["viewport"]
      expect(bounds["aspect"]).to be_within(0.001).of(bounds["imageAspect"])
    end
  ensure
    page.current_window.resize_to(1400, 900)
  end

  it "exports the dark variant's background and text without changing saved project colors" do
    project, = create_project_with_scene
    project.update!(settings: project.settings.merge("background_color" => "#ffffff", "caption_color" => "#000000"))
    visit editor_organization_screenshot_project_path(organization, project)
    expect_preview_ready
    find('[data-screenshot-editor-target="darkModeToggle"]').click
    find('[data-action="click->screenshot-export#openModal"]').click
    within("#export_modal") do
      find('[data-preset="ios_required"]').uncheck
      click_button "Export ZIP"
    end
    png = downloaded_images("screenshots.zip").values.sole
    expect(corner_pixel(png)).to eq([ 13, 13, 13, 255 ])
    # The source fixture is blue, with a blue-tinted white band. Bright neutral
    # pixels therefore come from the light caption, which must remain readable.
    bright_text_pixels = page.evaluate_async_script(<<~JS, Base64.strict_encode64(png))
      const [base64, done] = arguments;
      const image = new Image();
      image.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = image.width; canvas.height = image.height;
        const context = canvas.getContext("2d");
        context.drawImage(image, 0, 0);
        const pixels = context.getImageData(0, 0, image.width, image.height).data;
        let count = 0;
        for (let i = 0; i < pixels.length; i += 4) {
          if (pixels[i] > 230 && pixels[i] === pixels[i + 1] && pixels[i] === pixels[i + 2]) count++;
        }
        done(count);
      };
      image.src = "data:image/png;base64," + base64;
    JS
    expect(bright_text_pixels).to be > 20
    expect(project.reload.settings).to include("background_color" => "#ffffff", "caption_color" => "#000000")
  end
end
