require "rails_helper"

RSpec.describe ScreenshotProject, type: :model do
  let(:user) { User.create!(email: "screenshots@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }

  describe "validations" do
    it "is valid with valid attributes" do
      project = described_class.new(organization: organization, name: "My App Screenshots", platform: "both")
      expect(project).to be_valid
    end

    it "requires a name" do
      project = described_class.new(organization: organization, name: "", platform: "both")
      expect(project).not_to be_valid
      expect(project.errors[:name]).to include("can't be blank")
    end

    it "requires a platform" do
      project = described_class.new(organization: organization, name: "Test", platform: "")
      expect(project).not_to be_valid
    end

    it "validates platform inclusion" do
      project = described_class.new(organization: organization, name: "Test", platform: "windows")
      expect(project).not_to be_valid
      expect(project.errors[:platform]).to include("is not included in the list")
    end

    %w[ios android both].each do |platform|
      it "accepts '#{platform}' as a valid platform" do
        project = described_class.new(organization: organization, name: "Test #{platform}", platform: platform)
        expect(project).to be_valid
      end
    end

    it "validates template inclusion when present" do
      project = described_class.new(organization: organization, name: "Test", platform: "both", template: "nonexistent")
      expect(project).not_to be_valid
      expect(project.errors[:template]).to include("is not included in the list")
    end

    it "allows nil template (Custom)" do
      project = described_class.new(organization: organization, name: "Test", platform: "both", template: nil)
      expect(project).to be_valid
    end

    it "accepts valid template keys" do
      ScreenshotProject::TEMPLATE_KEYS.each do |key|
        project = described_class.new(organization: organization, name: "Test #{key}", platform: "both", template: key)
        expect(project).to be_valid, "Expected template '#{key}' to be valid"
      end
    end

    it "enforces unique name per organization" do
      described_class.create!(organization: organization, name: "Unique Name", platform: "ios")
      duplicate = described_class.new(organization: organization, name: "Unique Name", platform: "android")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("already exists for this organization")
    end

    it "allows same name in different organizations" do
      other_user = User.create!(email: "other-screenshots@example.com", password: "SecurePass123!", confirmed_at: Time.current)
      other_org = Organization.create!(name: "Other Org", owner: other_user)
      described_class.create!(organization: organization, name: "Same Name", platform: "ios")
      other_project = described_class.new(organization: other_org, name: "Same Name", platform: "ios")
      expect(other_project).to be_valid
    end
  end

  describe "plan limits" do
    it "limits free organizations to one screenshot project" do
      described_class.create!(organization: organization, name: "Project 1", platform: "both")

      second_project = described_class.new(organization: organization, name: "Project 2", platform: "both")

      expect(second_project).not_to be_valid
      expect(second_project.errors[:base]).to include("Organization has reached the maximum of 1 screenshot projects on the Free plan")
    end

    it "allows pro organizations to create up to ten screenshot projects" do
      organization.owner.update!(plan_tier: :pro)

      10.times do |i|
        described_class.create!(organization: organization, name: "Project #{i + 1}", platform: "both")
      end

      overflow = described_class.new(organization: organization, name: "Overflow", platform: "both")
      expect(overflow).not_to be_valid
      expect(overflow.errors[:base]).to include("Organization has reached the maximum of 10 screenshot projects on the Pro plan")
    end

    it "limits free projects to 5 scenes" do
      project = described_class.create!(organization: organization, name: "Scene Limit Free", platform: "both")
      expect(project.max_screenshot_scenes_per_project).to eq(5)

      5.times do |i|
        project.screenshot_scenes.create!(position: i + 1, source_image_data: "data#{i}")
      end

      sixth_scene = project.screenshot_scenes.build(position: 6, source_image_data: "data5")
      expect(sixth_scene).not_to be_valid
      expect(sixth_scene.errors[:base].first).to include("maximum of 5 scenes")
    end

    it "limits pro projects to 10 scenes" do
      organization.owner.update!(plan_tier: :pro)
      project = described_class.create!(organization: organization, name: "Scene Limit Pro", platform: "both")
      expect(project.max_screenshot_scenes_per_project).to eq(10)

      10.times do |i|
        project.screenshot_scenes.create!(position: i + 1, source_image_data: "data#{i}")
      end

      eleventh_scene = project.screenshot_scenes.build(position: 11, source_image_data: "data11")
      expect(eleventh_scene).not_to be_valid
      expect(eleventh_scene.errors[:base].first).to include("maximum of 10 scenes")
    end

    it "limits team projects to 15 scenes" do
      organization.owner.update!(plan_tier: :team)
      project = described_class.create!(organization: organization, name: "Scene Limit Team", platform: "both")
      expect(project.max_screenshot_scenes_per_project).to eq(15)
    end
  end

  describe "associations" do
    it "belongs to an organization" do
      project = described_class.create!(organization: organization, name: "Test", platform: "both")
      expect(project.organization).to eq(organization)
    end

    it "has many screenshot_scenes ordered by position" do
      project = described_class.create!(organization: organization, name: "Test", platform: "both")
      scene2 = project.screenshot_scenes.create!(position: 2, source_image_data: "data2", caption_text: "B")
      scene1 = project.screenshot_scenes.create!(position: 1, source_image_data: "data1", caption_text: "A")

      expect(project.screenshot_scenes).to eq([ scene1, scene2 ])
    end

    it "destroys scenes when project is destroyed" do
      project = described_class.create!(organization: organization, name: "Test", platform: "both")
      project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      expect { project.destroy }.to change(ScreenshotScene, :count).by(-1)
    end
  end

  describe "custom sticker images" do
    it "supports has_many_attached custom_sticker_images" do
      project = described_class.create!(organization: organization, name: "Custom Stickers", platform: "both")
      expect(project).to respond_to(:custom_sticker_images)
      expect(project.custom_sticker_images).to be_empty
    end

    it "defines ALLOWED_CUSTOM_STICKER_TYPES" do
      expect(ScreenshotProject::ALLOWED_CUSTOM_STICKER_TYPES).to eq(%w[image/png image/jpeg image/webp])
    end

    it "defines MAX_CUSTOM_STICKER_SIZE as 5 MB" do
      expect(ScreenshotProject::MAX_CUSTOM_STICKER_SIZE).to eq(5.megabytes)
    end

    it "defines MAX_CUSTOM_STICKERS_PER_PROJECT as 50" do
      expect(ScreenshotProject::MAX_CUSTOM_STICKERS_PER_PROJECT).to eq(50)
    end
  end

  describe "counter cache" do
    it "tracks scenes_count" do
      project = described_class.create!(organization: organization, name: "Test", platform: "both")
      expect(project.scenes_count).to eq(0)

      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")
      project.reload
      expect(project.scenes_count).to eq(1)

      scene.destroy
      project.reload
      expect(project.scenes_count).to eq(0)
    end
  end

  describe "constants" do
    it "defines EXPORT_PRESETS with all required keys" do
      expect(ScreenshotProject::EXPORT_PRESETS.keys).to include(
        "ios_required", "ios_optional", "ios_ipad",
        "android_phone", "android_tablet_7", "android_tablet_10"
      )
    end

    it "defines DEVICE_FRAMES with a 'none' option" do
      expect(ScreenshotProject::DEVICE_FRAMES).to have_key("none")
    end

    it "defines iOS required sizes correctly" do
      sizes = ScreenshotProject::EXPORT_PRESETS["ios_required"]
      dimensions = sizes.map { |s| [ s[:width], s[:height] ] }
      expect(dimensions).to include([ 1320, 2868 ], [ 1290, 2796 ], [ 1242, 2688 ])
    end

    it "defines Android phone size correctly" do
      sizes = ScreenshotProject::EXPORT_PRESETS["android_phone"]
      expect(sizes.first[:width]).to eq(1080)
      expect(sizes.first[:height]).to eq(1920)
    end
  end

  describe "DEFAULT_CUSTOM_SETTINGS" do
    it "includes all DEFAULT_TEXT_SETTINGS keys" do
      ScreenshotProject::DEFAULT_TEXT_SETTINGS.each_key do |key|
        expect(ScreenshotProject::DEFAULT_CUSTOM_SETTINGS).to have_key(key)
      end
    end

    it "includes extra keys for background, caption, device frame, and padding" do
      %w[background_type background_color caption_color caption_font_size caption_position device_frame screenshot_padding].each do |key|
        expect(ScreenshotProject::DEFAULT_CUSTOM_SETTINGS).to have_key(key), "Missing key: #{key}"
      end
    end
  end

  describe "TEMPLATE_KEYS" do
    it "matches TEMPLATES keys" do
      expect(ScreenshotProject::TEMPLATE_KEYS).to match_array(ScreenshotProject::TEMPLATES.keys)
    end
  end

  describe "TEMPLATES" do
    it "defines TEMPLATES constant" do
      expect(ScreenshotProject::TEMPLATES).to be_a(Hash)
      expect(ScreenshotProject::TEMPLATES).not_to be_empty
    end

    it "has 9 templates" do
      expect(ScreenshotProject::TEMPLATES.keys.size).to eq(9)
    end

    it "includes all expected template keys" do
      expected = %w[sunset_showcase geometric_bold neon_hero warm_editorial tech_grid value_promise feature_showcase social_proof playful_party]
      expect(ScreenshotProject::TEMPLATES.keys).to match_array(expected)
    end

    it "each template has required keys" do
      ScreenshotProject::TEMPLATES.each do |key, template|
        expect(template).to have_key(:label), "Template '#{key}' missing :label"
        expect(template).to have_key(:description), "Template '#{key}' missing :description"
        expect(template).to have_key(:settings), "Template '#{key}' missing :settings"
        expect(template[:settings]).to be_a(Hash)
        expect(template[:settings]).to have_key("caption_font_family"), "Template '#{key}' missing caption_font_family"
        expect(template[:settings]).to have_key("caption_color"), "Template '#{key}' missing caption_color"
      end
    end
  end

  describe ".template_settings" do
    it "returns settings for a valid template key" do
      settings = ScreenshotProject.template_settings("sunset_showcase")
      expected = ScreenshotProject::TEMPLATES["sunset_showcase"][:settings].except("default_stickers")
      expect(settings).to be_a(Hash)
      expect(settings).to eq(expected)
    end

    it "returns DEFAULT_TEXT_SETTINGS for an invalid key" do
      settings = ScreenshotProject.template_settings("nonexistent")
      expect(settings).to eq(ScreenshotProject::DEFAULT_TEXT_SETTINGS)
    end
  end

  describe "validate_background_image" do
    it "rejects invalid content type" do
      project = described_class.create!(organization: organization, name: "BG Validation", platform: "both")
      project.background_image.attach(
        io: StringIO.new("fake_gif_data"),
        filename: "bg.gif",
        content_type: "image/gif"
      )

      expect(project).not_to be_valid
      expect(project.errors[:background_image].first).to include("PNG, JPEG, or WebP")
    end

    it "rejects oversized file" do
      project = described_class.create!(organization: organization, name: "BG Size", platform: "both")
      project.background_image.attach(
        io: StringIO.new("x" * (11.megabytes)),
        filename: "bg.png",
        content_type: "image/png"
      )

      expect(project).not_to be_valid
      expect(project.errors[:background_image].first).to include("10 MB")
    end
  end

  describe ".org_export_storage_bytes" do
    it "returns 0 when no exports directory exists" do
      Rails.cache.clear
      bytes = described_class.org_export_storage_bytes(organization.id)
      expect(bytes).to eq(0)
    end

    it "calculates total bytes from files on disk" do
      project = described_class.create!(organization: organization, name: "Storage Test", platform: "both")
      dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join("screenshot_01.png"), "x" * 1024)
      File.binwrite(dir.join("screenshot_02.png"), "x" * 2048)

      Rails.cache.clear
      bytes = described_class.org_export_storage_bytes(organization.id)
      expect(bytes).to eq(3072)
    ensure
      FileUtils.rm_rf(project.exports_directory)
    end
  end

  describe "export path helpers" do
    it "creates a resolution directory under the exports root" do
      project = described_class.create!(organization: organization, name: "Export Helpers", platform: "both")

      dir = project.ensure_resolution_directory!(width: 1320, height: 2868)

      expect(dir).to eq(project.exports_directory.join("1320x2868"))
      expect(dir.exist?).to be(true)
      expect(dir.to_s).to start_with(described_class.exports_root.to_s)
    ensure
      project.clear_exports_directory! if project&.persisted?
    end

    it "removes export files via the rooted helper" do
      project = described_class.create!(organization: organization, name: "Export Cleanup", platform: "both")
      dir = project.ensure_resolution_directory!(width: 1320, height: 2868)
      File.binwrite(dir.join("screenshot_01.png"), "x" * 10)

      project.clear_exports_directory!

      expect(project.exports_directory.exist?).to be(false)
    end
  end

  describe ".invalidate_export_quota_cache!" do
    it "calls Rails.cache.delete with the correct key" do
      expect(Rails.cache).to receive(:delete).with("org_export_storage:#{organization.id}")
      described_class.invalidate_export_quota_cache!(organization.id)
    end
  end

  describe "#org_within_export_quota?" do
    it "returns true when under quota" do
      project = described_class.create!(organization: organization, name: "Quota Under", platform: "both")
      allow(described_class).to receive(:org_export_storage_bytes).and_return(100)

      expect(project.org_within_export_quota?(500)).to be true
    end

    it "returns false when over quota" do
      project = described_class.create!(organization: organization, name: "Quota Over", platform: "both")
      allow(described_class).to receive(:org_export_storage_bytes).and_return(project.max_export_storage_bytes_per_organization)

      expect(project.org_within_export_quota?(1)).to be false
    end
  end

  describe "locale support" do
    describe "APP_STORE_LOCALES" do
      it "defines a list of locale codes" do
        expect(ScreenshotProject::APP_STORE_LOCALES).to be_an(Array)
        expect(ScreenshotProject::APP_STORE_LOCALES).to include("en-US", "de-DE", "ja", "zh-Hans")
      end
    end

    describe "#multi_locale?" do
      it "returns false when locales is empty" do
        project = described_class.new(organization: organization, name: "Test", platform: "both", locales: [])
        expect(project.multi_locale?).to be false
      end

      it "returns true when locales has entries" do
        project = described_class.new(organization: organization, name: "Test", platform: "both", locales: [ "en-US", "de-DE" ])
        expect(project.multi_locale?).to be true
      end
    end

    describe "#default_locale" do
      it "returns en-US when locales is empty" do
        project = described_class.new(organization: organization, name: "Test", platform: "both", locales: [])
        expect(project.default_locale).to eq("en-US")
      end

      it "returns the first locale" do
        project = described_class.new(organization: organization, name: "Test", platform: "both", locales: [ "de-DE", "fr-FR" ])
        expect(project.default_locale).to eq("de-DE")
      end
    end

    describe "locale validations" do
      it "is valid with valid locale codes" do
        project = described_class.new(organization: organization, name: "Locales Test", platform: "both", locales: [ "en-US", "de-DE", "ja" ])
        expect(project).to be_valid
      end

      it "is valid with empty locales" do
        project = described_class.new(organization: organization, name: "No Locales", platform: "both", locales: [])
        expect(project).to be_valid
      end

      it "rejects locale codes not in APP_STORE_LOCALES" do
        project = described_class.new(organization: organization, name: "Bad Locale", platform: "both", locales: [ "invalid!!" ])
        expect(project).not_to be_valid
        expect(project.errors[:locales].first).to include("unsupported locale")
      end

      it "rejects well-formatted but unsupported locale codes" do
        project = described_class.new(organization: organization, name: "Nonsense Locale", platform: "both", locales: [ "xx-YY" ])
        expect(project).not_to be_valid
        expect(project.errors[:locales].first).to include("unsupported locale")
        expect(project.errors[:locales].first).to include("Must be one of")
      end

      it "rejects more than MAX_LOCALES locales" do
        # Duplicate valid locales to exceed the limit (validation checks count before checking membership)
        many_locales = (ScreenshotProject::APP_STORE_LOCALES * 2).first(ScreenshotProject::MAX_LOCALES + 1)
        project = described_class.new(organization: organization, name: "Too Many", platform: "both", locales: many_locales)
        expect(project).not_to be_valid
        expect(project.errors[:locales].first).to include("cannot have more than")
      end
    end
  end
end
