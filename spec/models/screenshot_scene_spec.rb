require "rails_helper"

RSpec.describe ScreenshotScene, type: :model do
  let(:user) { User.create!(email: "scenes@example.com", password: "SecurePass123!", confirmed_at: Time.current, plan_tier: :pro) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }
  let(:project) { ScreenshotProject.create!(organization: organization, name: "Test Project", platform: "both") }

  describe "validations" do
    it "is valid with valid attributes" do
      scene = described_class.new(
        screenshot_project: project,
        position: 1,
        source_image_data: "image_data",
        source_image_content_type: "image/png"
      )
      expect(scene).to be_valid
    end

    it "requires an image (ActiveStorage or binary data)" do
      scene = described_class.new(screenshot_project: project, position: 1, source_image_data: nil)
      expect(scene).not_to be_valid
      expect(scene.errors[:base]).to include("An image is required")
    end

    it "validates content_type inclusion" do
      scene = described_class.new(
        screenshot_project: project,
        position: 1,
        source_image_data: "data",
        source_image_content_type: "image/gif"
      )
      expect(scene).not_to be_valid
      expect(scene.errors[:source_image_content_type]).to include("is not included in the list")
    end

    %w[image/png image/jpeg].each do |content_type|
      it "accepts '#{content_type}' as valid content type" do
        scene = described_class.new(
          screenshot_project: project,
          position: 1,
          source_image_data: "data",
          source_image_content_type: content_type
        )
        expect(scene).to be_valid
      end
    end
  end

  describe "auto-set position" do
    it "assigns position automatically when not provided" do
      scene = described_class.create!(screenshot_project: project, source_image_data: "data1")
      expect(scene.position).to eq(1)
    end

    it "increments position based on existing scenes" do
      described_class.create!(screenshot_project: project, source_image_data: "data1", position: 1)
      scene2 = described_class.create!(screenshot_project: project, source_image_data: "data2")
      expect(scene2.position).to eq(2)
    end

    it "respects explicitly provided position" do
      scene = described_class.create!(screenshot_project: project, source_image_data: "data", position: 5)
      expect(scene.position).to eq(5)
    end
  end

  describe "associations" do
    it "belongs to a screenshot_project" do
      scene = described_class.create!(screenshot_project: project, source_image_data: "data", position: 1)
      expect(scene.screenshot_project).to eq(project)
    end
  end

  describe "counter cache" do
    it "updates the project scenes_count" do
      expect { described_class.create!(screenshot_project: project, source_image_data: "data") }
        .to change { project.reload.scenes_count }.from(0).to(1)
    end
  end

  describe "#effective_settings" do
    it "returns project settings when no overrides" do
      project.update!(settings: { "caption_color" => "#FF0000", "caption_font_size" => 48 })
      scene = described_class.create!(screenshot_project: project, source_image_data: "data", position: 1, overrides: {})
      expect(scene.effective_settings).to eq({ "caption_color" => "#FF0000", "caption_font_size" => 48 })
    end

    it "merges scene overrides on top of project settings" do
      project.update!(settings: { "caption_color" => "#FF0000", "caption_font_size" => 48 })
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        overrides: { "caption_color" => "#00FF00" }
      )
      expect(scene.effective_settings).to eq({ "caption_color" => "#00FF00", "caption_font_size" => 48 })
    end

    it "handles nil overrides gracefully" do
      project.update!(settings: { "caption_color" => "#FF0000" })
      scene = described_class.create!(screenshot_project: project, source_image_data: "data", position: 1)
      scene.update_column(:overrides, nil)
      scene.reload
      expect(scene.effective_settings).to eq({ "caption_color" => "#FF0000" })
    end
  end

  describe "#custom_text_position?" do
    it "returns true when both text_position_x and text_position_y are present" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        overrides: { "text_position_x" => 50.0, "text_position_y" => 30.0 }
      )
      expect(scene.custom_text_position?).to be true
    end

    it "returns false when drag positions are not set" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        overrides: { "caption_color" => "#FF0000" }
      )
      expect(scene.custom_text_position?).to be false
    end

    it "returns false when overrides are empty" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        overrides: {}
      )
      expect(scene.custom_text_position?).to be false
    end

    it "returns false when overrides are nil" do
      scene = described_class.create!(screenshot_project: project, source_image_data: "data", position: 1)
      scene.update_column(:overrides, nil)
      scene.reload
      expect(scene.custom_text_position?).to be false
    end
  end

  describe "#text_position_x" do
    it "returns the x position from overrides" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        overrides: { "text_position_x" => 42.5 }
      )
      expect(scene.text_position_x).to eq(42.5)
    end

    it "returns nil when not set" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        overrides: {}
      )
      expect(scene.text_position_x).to be_nil
    end
  end

  describe "#text_position_y" do
    it "returns the y position from overrides" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        overrides: { "text_position_y" => 65.3 }
      )
      expect(scene.text_position_y).to eq(65.3)
    end

    it "returns nil when not set" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        overrides: {}
      )
      expect(scene.text_position_y).to be_nil
    end
  end

  describe "#copy_to_project" do
    let(:target_project) { ScreenshotProject.create!(organization: organization, name: "Target Project", platform: "both") }

    it "copies a scene to the target project" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        caption_text: "Hello", subtitle_text: "World",
        overrides: { "caption_color" => "#FF0000" }
      )

      new_scene = scene.copy_to_project(target_project)

      expect(new_scene).to be_persisted
      expect(new_scene.screenshot_project).to eq(target_project)
      expect(new_scene.caption_text).to eq("Hello")
      expect(new_scene.subtitle_text).to eq("World")
      expect(new_scene.overrides).to eq({ "caption_color" => "#FF0000" })
    end

    it "copies locale_variants" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        caption_text: "Hello",
        locale_variants: { "de-DE" => { "caption_text" => "Hallo" } }
      )

      new_scene = scene.copy_to_project(target_project)

      expect(new_scene.locale_variants).to eq({ "de-DE" => { "caption_text" => "Hallo" } })
    end

    it "auto-assigns position in the target project" do
      target_project.screenshot_scenes.create!(source_image_data: "existing", position: 1)
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        caption_text: "Copy me"
      )

      new_scene = scene.copy_to_project(target_project)

      expect(new_scene.position).to eq(2)
    end

    it "returns nil when target project is at scene limit" do
      # Fill target project to the limit
      target_project.max_screenshot_scenes_per_project.times do |i|
        target_project.screenshot_scenes.create!(source_image_data: "data#{i}", position: i + 1)
      end

      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        caption_text: "Won't fit"
      )

      result = scene.copy_to_project(target_project)

      expect(result).to be_nil
    end

    it "rejects copying a legacy binary scene when the org media cap would be exceeded" do
      scene = described_class.create!(
        screenshot_project: project,
        source_image_data: "legacy-image-bytes",
        position: 1,
        caption_text: "Too large to copy"
      )

      expect(target_project).to receive(:org_within_media_quota?)
        .with("legacy-image-bytes".bytesize, use_cache: false)
        .and_return(false)

      result = scene.copy_to_project(target_project)

      expect(result).to be_nil
      expect(scene.errors[:base].join(" ")).to match(/media quota exceeded/i)
    end
  end

  describe "#caption_for_locale" do
    it "returns caption_text for blank locale" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        caption_text: "English"
      )
      expect(scene.caption_for_locale(nil)).to eq("English")
      expect(scene.caption_for_locale("")).to eq("English")
    end

    it "returns locale-specific caption when available" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        caption_text: "English",
        locale_variants: { "de-DE" => { "caption_text" => "Deutsch" } }
      )
      expect(scene.caption_for_locale("de-DE")).to eq("Deutsch")
    end

    it "falls back to caption_text when locale variant is missing" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        caption_text: "English",
        locale_variants: {}
      )
      expect(scene.caption_for_locale("fr-FR")).to eq("English")
    end
  end

  describe "#subtitle_for_locale" do
    it "returns subtitle_text for blank locale" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        subtitle_text: "Sub English"
      )
      expect(scene.subtitle_for_locale(nil)).to eq("Sub English")
    end

    it "returns locale-specific subtitle when available" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        subtitle_text: "Sub English",
        locale_variants: { "ja" => { "subtitle_text" => "Japanese Sub" } }
      )
      expect(scene.subtitle_for_locale("ja")).to eq("Japanese Sub")
    end

    it "falls back to subtitle_text when locale variant is missing" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        subtitle_text: "Sub English",
        locale_variants: {}
      )
      expect(scene.subtitle_for_locale("ko")).to eq("Sub English")
    end
  end

  describe "validate_locale_variants" do
    it "rejects more than 50 locale entries" do
      variants = {}
      51.times do |i|
        variants["xx-#{('AA'..'ZZ').to_a[i]}"] = { "caption_text" => "Text #{i}" }
      end

      scene = described_class.new(
        screenshot_project: project, source_image_data: "data", position: 1,
        locale_variants: variants
      )
      expect(scene).not_to be_valid
      expect(scene.errors[:locale_variants].first).to include("more than 50")
    end

    it "rejects text values exceeding 500 characters" do
      scene = described_class.new(
        screenshot_project: project, source_image_data: "data", position: 1,
        locale_variants: { "de-DE" => { "caption_text" => "A" * 501 } }
      )
      expect(scene).not_to be_valid
      expect(scene.errors[:locale_variants].first).to include("500 characters")
    end

    it "is valid with well-formed locale_variants" do
      scene = described_class.new(
        screenshot_project: project, source_image_data: "data", position: 1,
        locale_variants: {
          "de-DE" => { "caption_text" => "Deutsch", "subtitle_text" => "Unter" },
          "fr-FR" => { "caption_text" => "Francais" }
        }
      )
      expect(scene).to be_valid
    end
  end

  describe "#set_locale_text" do
    it "sets caption and subtitle for a locale" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        caption_text: "English"
      )

      scene.set_locale_text("de-DE", caption: "Deutsch", subtitle: "Untertitel")

      expect(scene.locale_variants["de-DE"]["caption_text"]).to eq("Deutsch")
      expect(scene.locale_variants["de-DE"]["subtitle_text"]).to eq("Untertitel")
    end

    it "merges with existing locale variants" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        locale_variants: { "de-DE" => { "caption_text" => "Deutsch" } }
      )

      scene.set_locale_text("fr-FR", caption: "Francais")

      expect(scene.locale_variants["de-DE"]["caption_text"]).to eq("Deutsch")
      expect(scene.locale_variants["fr-FR"]["caption_text"]).to eq("Francais")
    end

    it "updates existing locale entry" do
      scene = described_class.create!(
        screenshot_project: project, source_image_data: "data", position: 1,
        locale_variants: { "de-DE" => { "caption_text" => "Alt" } }
      )

      scene.set_locale_text("de-DE", caption: "Neu")

      expect(scene.locale_variants["de-DE"]["caption_text"]).to eq("Neu")
    end
  end
end
