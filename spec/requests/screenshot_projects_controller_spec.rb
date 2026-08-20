require "rails_helper"
require "fileutils"

RSpec.describe "ScreenshotProjectsController", type: :request do
  let(:user) { User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro, onboarding_completed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }

  before do
    sign_in user, scope: :user
  end

  describe "GET /organizations/:organization_id/screenshot_projects" do
    it "renders successfully" do
      get organization_screenshot_projects_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it "displays existing projects" do
      ScreenshotProject.create!(organization: organization, name: "My App v1", platform: "ios")
      get organization_screenshot_projects_path(organization)
      expect(response.body).to include("My App v1")
    end

    it "shows overflow warnings and badges when the current plan is exceeded" do
      user.update!(plan_tier: :pro)
      project_1 = ScreenshotProject.create!(organization: organization, name: "Project 1", platform: "both", created_at: 2.days.ago)
      project_2 = ScreenshotProject.create!(organization: organization, name: "Project 2", platform: "both", created_at: 1.day.ago)

      user.update!(plan_tier: :free)

      get organization_screenshot_projects_path(organization)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Usage exceeds plan limits")
      expect(response.body).to include("Overflow")
      expect(response.body).to include(project_2.name)
      expect(response.body).not_to include(project_1.name + "</span>\n                      <span class=\"badge badge-warning badge-xs\">Overflow</span>")
    end

    it "attaches an upgrade gate to overflow project links" do
      user.update!(plan_tier: :pro)
      ScreenshotProject.create!(organization: organization, name: "Project 1", platform: "both", created_at: 2.days.ago)
      overflow_project = ScreenshotProject.create!(organization: organization, name: "Project 2", platform: "both", created_at: 1.day.ago)
      user.update!(plan_tier: :free)

      get organization_screenshot_projects_path(organization)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(overflow_project.name)
      expect(response.body).to include('data-upgrade-gate-blocked-value="true"')
      expect(response.body).to include("unlock this screenshot project")
    end
  end

  describe "GET /organizations/:organization_id/screenshot_projects/new" do
    it "renders the new form" do
      get new_organization_screenshot_project_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it "renders the project-create gate state at the free plan cap" do
      user.update!(plan_tier: :free)
      ScreenshotProject.create!(organization: organization, name: "Existing Project", platform: "both")

      get new_organization_screenshot_project_path(organization)

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      form = doc.at_css("form")
      prompt = JSON.parse(form["data-upgrade-gate-prompt-value"])

      expect(form["data-upgrade-gate-blocked-value"]).to eq("true")
      expect(prompt).to include(
        "current_plan" => "free",
        "required_plan" => "pro",
        "feature" => "screenshot project",
        "source" => "screenshot_projects#new:create-project"
      )
    end
  end

  describe "POST /organizations/:organization_id/screenshot_projects" do
    it "creates a project and redirects to editor" do
      expect {
        post organization_screenshot_projects_path(organization), params: {
          screenshot_project: { name: "New Screenshots", platform: "both" }
        }
      }.to change(ScreenshotProject, :count).by(1)

      project = ScreenshotProject.last
      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
    end

    it "renders errors for invalid input" do
      post organization_screenshot_projects_path(organization), params: {
        screenshot_project: { name: "", platform: "both" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects invalid platform" do
      post organization_screenshot_projects_path(organization), params: {
        screenshot_project: { name: "Test", platform: "windows" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "enforces the free-plan project cap through the controller" do
      user.update!(plan_tier: :free)
      ScreenshotProject.create!(organization: organization, name: "Existing Project", platform: "both")

      expect {
        post organization_screenshot_projects_path(organization), params: {
          screenshot_project: { name: "One Too Many", platform: "both" }
        }
      }.not_to change(ScreenshotProject, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("maximum of 1 screenshot projects")
      expect(response.body).to include("Upgrade from Free to Pro to increase the screenshot project limit.")
    end

    it "returns a structured quota response for JSON requests when the project cap is reached" do
      user.update!(plan_tier: :free)
      ScreenshotProject.create!(organization: organization, name: "Existing Project", platform: "both")

      expect {
        post organization_screenshot_projects_path(organization), params: {
          screenshot_project: { name: "One Too Many", platform: "both" }
        }, headers: { "Accept" => "application/json" }
      }.not_to change(ScreenshotProject, :count)

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("quota_exhausted")
      expect(json["current_plan"]).to eq("free")
      expect(json["next_plan"]).to eq("pro")
      expect(json["suggestion"]).to include("Upgrade from Free to Pro")
    end
  end

  describe "GET /organizations/:organization_id/screenshot_projects/:id (show)" do
    it "redirects to editor" do
      project = ScreenshotProject.create!(organization: organization, name: "Test", platform: "both")
      get organization_screenshot_project_path(organization, project)
      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
    end
  end

  describe "GET /organizations/:organization_id/screenshot_projects/:id/edit" do
    it "renders the edit form" do
      project = ScreenshotProject.create!(organization: organization, name: "Test", platform: "both")
      get edit_organization_screenshot_project_path(organization, project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Test")
    end
  end

  describe "PATCH /organizations/:organization_id/screenshot_projects/:id" do
    it "updates the project" do
      project = ScreenshotProject.create!(organization: organization, name: "Old Name", platform: "ios")

      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: { name: "New Name", platform: "android" }
      }

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
      project.reload
      expect(project.name).to eq("New Name")
      expect(project.platform).to eq("android")
    end

    it "renders errors for invalid update" do
      project = ScreenshotProject.create!(organization: organization, name: "Test", platform: "ios")

      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: { name: "" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /organizations/:organization_id/screenshot_projects/:id" do
    it "deletes the project and redirects to index" do
      project = ScreenshotProject.create!(organization: organization, name: "Delete Me", platform: "both")

      expect {
        delete organization_screenshot_project_path(organization, project)
      }.to change(ScreenshotProject, :count).by(-1)

      expect(response).to redirect_to(organization_screenshot_projects_path(organization))
    end

    it "still deletes the project and its export files after an export quota rejection" do
      project = ScreenshotProject.create!(organization: organization, name: "Quota Delete", platform: "both")
      project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "Export me")
      export_dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(export_dir)
      File.binwrite(export_dir.join("screenshot_01.png"), "fake_png")

      allow_any_instance_of(ScreenshotProject).to receive(:org_within_export_quota?).and_return(false)
      file = Rack::Test::UploadedFile.new(
        StringIO.new(valid_png_bytes), "image/png", true, original_filename: "shot.png"
      )

      post upload_export_organization_screenshot_project_path(organization, project), params: {
        screenshots: [
          { file: file, width: 1320, height: 2868, scene_position: 1 }
        ]
      }

      expect(response).to have_http_status(:unprocessable_content)

      delete organization_screenshot_project_path(organization, project)

      expect(response).to redirect_to(organization_screenshot_projects_path(organization))
      expect(Dir.exist?(project.exports_directory)).to be false
    end
  end

  describe "GET /organizations/:organization_id/screenshot_projects/:id/editor" do
    it "renders the editor" do
      project = ScreenshotProject.create!(organization: organization, name: "Editor Test", platform: "both")
      get editor_organization_screenshot_project_path(organization, project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Screenshot Studio")
    end

    it "redirects overflow projects to the oldest allowed project" do
      user.update!(plan_tier: :pro)
      project_1 = ScreenshotProject.create!(organization: organization, name: "Project 1", platform: "both", created_at: 2.days.ago)
      project_2 = ScreenshotProject.create!(organization: organization, name: "Project 2", platform: "both", created_at: 1.day.ago)

      user.update!(plan_tier: :free)

      get editor_organization_screenshot_project_path(organization, project_2)

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project_1))
      follow_redirect!
      expect(response.body).to include("upgrade-prompt-callout")
      expect(response.body).to include("unlock this screenshot project")
      expect(response.body).to include("Project 1")
    end

    it "still renders the editor when media usage is already over the limit" do
      project = ScreenshotProject.create!(organization: organization, name: "Media Limit Test", platform: "both")
      project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "x" * 200,
        source_image_content_type: "image/png",
        caption_text: "Consumes quota"
      )
      allow_any_instance_of(ScreenshotProject).to receive(:max_media_storage_bytes_per_organization).and_return(250)

      get editor_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Screenshot Studio")
      expect(response.body).to include(project.name)
    end

    it "shows a plan-aware upgrade state for free plans" do
      user.update!(plan_tier: :free)
      AppStoreConnectCredential.create!(
        organization: organization,
        name: "Primary ASC",
        key_id: "FREE1234",
        issuer_id: "11111111-1111-1111-1111-111111111111",
        private_key: OpenSSL::PKey::EC.generate("prime256v1").to_pem,
        team_id: "TEAMFREE1",
        active: true
      )
      project = ScreenshotProject.create!(organization: organization, name: "Locked Uploads", platform: "ios")

      get editor_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Upload")
      expect(response.body).to include('data-screenshot-store-upload-store-uploads-enabled-value="false"')
      expect(response.body).to include("upgrade-prompt-callout")
      expect(response.body).to include('data-upgrade-prompt-target="panel"')
      expect(response.body).to include("See plans")
      expect(response.body).not_to include("Maybe later")
    end

    it "redirects overflow projects back to the oldest allowed project and shows the upgrade prompt" do
      user.update!(plan_tier: :pro)
      oldest_project = ScreenshotProject.create!(organization: organization, name: "Project 1", platform: "both", created_at: 2.days.ago)
      overflow_project = ScreenshotProject.create!(organization: organization, name: "Project 2", platform: "both", created_at: 1.day.ago)
      user.update!(plan_tier: :free)

      get editor_organization_screenshot_project_path(organization, overflow_project)

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, oldest_project))
      follow_redirect!
      expect(response.body).to include("upgrade-prompt-callout")
      expect(response.body).to include("unlock this screenshot project")
      expect(response.body).to include(oldest_project.name)
    end
  end

  describe "POST create with template" do
    it "applies template settings when a valid template is provided" do
      post organization_screenshot_projects_path(organization), params: {
        screenshot_project: { name: "Templated Project", platform: "both", template: "geometric_bold" }
      }

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, ScreenshotProject.last))
      project = ScreenshotProject.last
      expect(project.template).to eq("geometric_bold")
      expect(project.settings["caption_font_family"]).to eq("Anton")
      expect(project.settings["background_type"]).to eq("pattern")
    end

    it "template fully overrides form Default Appearance fields" do
      post organization_screenshot_projects_path(organization), params: {
        screenshot_project: {
          name: "Override Test", platform: "both", template: "sunset_showcase",
          settings: { background_color: "#FF0000", caption_position: "bottom", device_frame: "none" }
        }
      }

      project = ScreenshotProject.last
      template_settings = ScreenshotProject::TEMPLATES["sunset_showcase"][:settings]
      expect(project.template).to eq("sunset_showcase")
      # Template settings should fully replace form fields
      expect(project.settings["background_type"]).to eq(template_settings["background_type"])
      expect(project.settings["caption_position"]).to eq(template_settings["caption_position"])
      expect(project.settings["device_frame"]).to eq(template_settings["device_frame"])
    end

    it "uses Custom defaults merged with form fields when no template" do
      post organization_screenshot_projects_path(organization), params: {
        screenshot_project: {
          name: "Custom Project", platform: "both", template: "",
          settings: { background_color: "#FF0000", caption_position: "top" }
        }
      }

      project = ScreenshotProject.last
      expect(project.template).to be_nil
      expect(project.settings["background_color"]).to eq("#FF0000")
      expect(project.settings["caption_position"]).to eq("top")
      # DEFAULT_CUSTOM_SETTINGS keys should be present
      expect(project.settings["caption_font_family"]).to eq("Inter")
      expect(project.settings["device_frame"]).to eq("none")
    end

    it "ignores invalid template keys and falls back to custom" do
      post organization_screenshot_projects_path(organization), params: {
        screenshot_project: { name: "No Template", platform: "both", template: "nonexistent_template" }
      }

      project = ScreenshotProject.last
      expect(project.template).to be_nil
    end

    it "works without a template param" do
      post organization_screenshot_projects_path(organization), params: {
        screenshot_project: { name: "Plain Project", platform: "both" }
      }

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, ScreenshotProject.last))
    end
  end

  describe "PATCH update with template" do
    it "replaces settings with template when template is selected" do
      project = ScreenshotProject.create!(
        organization: organization, name: "Test", platform: "both",
        settings: { "background_color" => "#FF0000", "caption_color" => "#00FF00" }
      )

      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: { template: "warm_editorial" }
      }

      project.reload
      expect(project.template).to eq("warm_editorial")
      expect(project.settings["caption_font_family"]).to eq("Playfair Display")
      expect(project.settings["background_type"]).to eq("gradient")
    end

    it "applies template text and scene-level defaults to every existing scene on HTML settings save" do
      template_key = "playful_party"
      template_settings = ScreenshotProject::TEMPLATES.fetch(template_key).fetch(:settings)
      project = ScreenshotProject.create!(
        organization: organization, name: "Template All Scenes", platform: "both",
        settings: { "background_color" => "#111111" }
      )

      scene1 = project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "data-1",
        caption_text: "Old One",
        subtitle_text: "Old Sub One",
        overrides: {
          "caption_color" => "#FF0000",
          "text_position_x" => 12.3,
          "text_position_y" => 45.6,
          "stickers" => [ { "id" => "old_s1", "type" => "emoji", "emoji" => "🔥", "x" => 50, "y" => 50, "size" => 48, "rotation" => 0 } ]
        }
      )
      scene2 = project.screenshot_scenes.create!(
        position: 2,
        source_image_data: "data-2",
        caption_text: "",
        subtitle_text: "",
        overrides: {
          "caption_color" => "#00FF00",
          "stickers" => [ { "id" => "old_s2", "type" => "emoji", "emoji" => "⭐", "x" => 20, "y" => 20, "size" => 60, "rotation" => 0 } ]
        }
      )

      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: { template: template_key }
      }

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))

      project.reload
      expect(project.template).to eq(template_key)

      [ scene1, scene2 ].each do |scene|
        scene.reload
        expect(scene.caption_text).to eq(template_settings["caption_text"])
        expect(scene.subtitle_text).to eq(template_settings["subtitle_text"])
        expect(scene.overrides["text_position_x"]).to eq(template_settings["text_position_x"])
        expect(scene.overrides["text_position_y"]).to eq(template_settings["text_position_y"])
        expect(scene.overrides["stickers"]).to be_an(Array)
        expect(scene.overrides["stickers"].size).to eq(template_settings["default_stickers"].size)
        expect(scene.overrides).not_to have_key("caption_color")
        scene.overrides["stickers"].each do |sticker|
          expect(sticker["id"]).to be_present
        end
      end
    end

    it "does not overwrite scene text or overrides on JSON project updates" do
      project = ScreenshotProject.create!(
        organization: organization, name: "JSON Save", platform: "both",
        settings: { "caption_color" => "#123456" }
      )
      scene = project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "data",
        caption_text: "Keep this text",
        subtitle_text: "Keep this subtitle",
        overrides: {
          "text_position_x" => 22.2,
          "text_position_y" => 77.7,
          "stickers" => [ { "id" => "persist_me", "type" => "emoji", "emoji" => "✅", "x" => 50, "y" => 50, "size" => 48, "rotation" => 0 } ]
        }
      )

      patch organization_screenshot_project_path(organization, project),
            params: { screenshot_project: { template: "playful_party" } },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      scene.reload
      expect(scene.caption_text).to eq("Keep this text")
      expect(scene.subtitle_text).to eq("Keep this subtitle")
      expect(scene.overrides["text_position_x"]).to eq(22.2)
      expect(scene.overrides["text_position_y"]).to eq(77.7)
      expect(scene.overrides["stickers"].first["id"]).to eq("persist_me")
    end

    it "switches to custom and preserves existing settings merged with form" do
      project = ScreenshotProject.create!(
        organization: organization, name: "Test", platform: "both",
        template: "warm_editorial",
        settings: { "caption_font_family" => "Playfair Display", "gradient_start" => "#FEF3C7", "caption_color" => "#451A03" }
      )

      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: { template: "", settings: { gradient_start: "#000000" } }
      }

      project.reload
      expect(project.template).to be_nil
      expect(project.settings["gradient_start"]).to eq("#000000")
      # Existing settings not overridden by form should be preserved
      expect(project.settings["caption_font_family"]).to eq("Playfair Display")
    end

    it "does not touch template when no template param is sent (editor JSON save)" do
      project = ScreenshotProject.create!(
        organization: organization, name: "Test", platform: "both",
        template: "warm_editorial",
        settings: { "caption_font_family" => "Playfair Display", "caption_color" => "#451A03" }
      )

      patch organization_screenshot_project_path(organization, project),
            params: { screenshot_project: { settings: { caption_color: "#FFFFFF" } } },
            headers: { "Accept" => "application/json" }

      project.reload
      expect(project.template).to eq("warm_editorial")
      expect(project.settings["caption_color"]).to eq("#FFFFFF")
      expect(project.settings["caption_font_family"]).to eq("Playfair Display")
    end
  end

  describe "POST apply_template" do
    it "applies template settings and persists the template key" do
      project = ScreenshotProject.create!(organization: organization, name: "Test", platform: "both", settings: {})

      post apply_template_organization_screenshot_project_path(organization, project),
           params: { template_key: "sunset_showcase" },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      template_settings = ScreenshotProject::TEMPLATES["sunset_showcase"][:settings]
      expect(json["status"]).to eq("ok")
      expect(json["settings"]["caption_font_family"]).to eq(template_settings["caption_font_family"])
      expect(json["settings"]["caption_color"]).to eq(template_settings["caption_color"])

      project.reload
      expect(project.template).to eq("sunset_showcase")
    end

    it "returns error for invalid template key" do
      project = ScreenshotProject.create!(organization: organization, name: "Test", platform: "both")

      post apply_template_organization_screenshot_project_path(organization, project),
           params: { template_key: "invalid" },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "merges template settings with existing settings" do
      project = ScreenshotProject.create!(
        organization: organization, name: "Test", platform: "both",
        settings: { "custom_key" => "custom_value", "caption_color" => "#AAAAAA" }
      )

      post apply_template_organization_screenshot_project_path(organization, project),
           params: { template_key: "warm_editorial" },
           headers: { "Accept" => "application/json" }

      project.reload
      template_settings = ScreenshotProject::TEMPLATES["warm_editorial"][:settings]
      expect(project.template).to eq("warm_editorial")
      expect(project.settings["custom_key"]).to eq("custom_value")
      expect(project.settings["caption_color"]).to eq(template_settings["caption_color"])
    end
  end

  describe "PATCH update with locales" do
    it "saves locales on a project" do
      project = ScreenshotProject.create!(organization: organization, name: "Locale Project", platform: "both")

      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: { locales: [ "en-US", "de-DE", "ja" ] }
      }

      project.reload
      expect(project.locales).to eq([ "en-US", "de-DE", "ja" ])
      expect(project.multi_locale?).to be true
    end

    it "clears locales when empty string is the only value" do
      project = ScreenshotProject.create!(organization: organization, name: "Clear Locale", platform: "both", locales: [ "en-US" ])

      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: { locales: [ "" ] }
      }

      project.reload
      # The hidden field sends [""] when all checkboxes are unchecked
      # before_validation strips blank strings, resulting in empty locales
      expect(project.locales).to eq([])
      expect(project.multi_locale?).to be false
    end

    it "saves locales when submitted with all form fields (like real form)" do
      project = ScreenshotProject.create!(
        organization: organization, name: "Full Form", platform: "both",
        settings: { "caption_color" => "#FFF", "background_color" => "#000", "caption_position" => "top", "device_frame" => "none" }
      )

      # Mimic the EXACT form submission: all fields including settings, name, platform, and locales with hidden empty value
      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: {
          name: "Full Form",
          platform: "both",
          locales: [ "en-US", "da", "es-MX", "hi", "" ],
          settings: { background_color: "#000000", caption_position: "top", device_frame: "none" }
        }
      }

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
      project.reload
      expect(project.locales).to eq([ "en-US", "da", "es-MX", "hi" ])
      expect(project.multi_locale?).to be true
      # Verify settings were also saved correctly
      expect(project.settings["caption_color"]).to eq("#FFF") # preserved from existing
      expect(project.settings["background_color"]).to eq("#000000") # updated
    end

    it "rejects invalid locale codes" do
      project = ScreenshotProject.create!(organization: organization, name: "Bad Locale Proj", platform: "both")

      patch organization_screenshot_project_path(organization, project), params: {
        screenshot_project: { locales: [ "invalid!!" ] }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET editor with locales" do
    it "renders locale tabs when project has locales" do
      project = ScreenshotProject.create!(organization: organization, name: "Multi-locale", platform: "both", locales: [ "en-US", "de-DE" ])

      get editor_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("en-US")
      expect(response.body).to include("de-DE")
      expect(response.body).to include("Locale")
    end

    it "does not render locale tabs when project has no locales" do
      project = ScreenshotProject.create!(organization: organization, name: "No locale", platform: "both", locales: [])

      get editor_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-screenshot-editor-target=\"localeBar\"")
    end
  end

  describe "GET editor with bulk edit" do
    it "renders the bulk edit button when scenes exist" do
      project = ScreenshotProject.create!(organization: organization, name: "Bulk Edit Test", platform: "both")
      project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "Scene 1")

      get editor_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bulk Edit")
      expect(response.body).to include("bulk_edit_modal")
    end
  end

  describe "GET editor with copy scene modal" do
    it "renders copy scene modal when other projects exist" do
      project = ScreenshotProject.create!(organization: organization, name: "Source", platform: "both")
      ScreenshotProject.create!(organization: organization, name: "Target", platform: "both")
      project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      get editor_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("copy_scene_modal")
      expect(response.body).to include("Target")
    end
  end

  describe "POST upload_custom_sticker_image" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "Sticker Upload Test", platform: "both") }

    it "uploads a valid PNG image" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_image.png"), "image/png")

      post upload_custom_sticker_image_organization_screenshot_project_path(organization, project),
           params: { file: file },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["id"]).to be_present
      expect(json["url"]).to be_present
      expect(json["filename"]).to be_present
      expect(project.custom_sticker_images.count).to eq(1)
    end

    it "rejects invalid file type" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_file.txt"), "text/plain")

      post upload_custom_sticker_image_organization_screenshot_project_path(organization, project),
           params: { file: file },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["message"]).to include("PNG, JPEG, or WebP")
    end

    it "rejects missing file" do
      post upload_custom_sticker_image_organization_screenshot_project_path(organization, project),
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "blocks uploads when media quota is exhausted but still allows sticker cleanup" do
      project.custom_sticker_images.attach(
        io: StringIO.new(valid_png_bytes),
        filename: "existing-sticker.png",
        content_type: "image/png"
      )
      other_project = ScreenshotProject.create!(organization: organization, name: "Quota Stickers", platform: "both")
      other_project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "x" * 200,
        source_image_content_type: "image/png",
        caption_text: "Consumes quota"
      )
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_image.png"), "image/png")

      allow_any_instance_of(ScreenshotProject).to receive(:max_media_storage_bytes_per_organization).and_return(250)

      post upload_custom_sticker_image_organization_screenshot_project_path(organization, project),
           params: { file: file },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("quota exceeded")

      signed_id = project.custom_sticker_images.last.blob.signed_id
      delete delete_custom_sticker_image_organization_screenshot_project_path(organization, project),
             params: { signed_id: signed_id },
             headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(project.reload.custom_sticker_images.count).to eq(0)
    end
  end

  describe "DELETE delete_custom_sticker_image" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "Sticker Delete Test", platform: "both") }

    it "deletes an existing custom sticker image" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_image.png"), "image/png")
      project.custom_sticker_images.attach(file)
      signed_id = project.custom_sticker_images.last.blob.signed_id

      delete delete_custom_sticker_image_organization_screenshot_project_path(organization, project),
             params: { signed_id: signed_id },
             headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(project.reload.custom_sticker_images.count).to eq(0)
    end

    it "returns not found for invalid signed_id" do
      delete delete_custom_sticker_image_organization_screenshot_project_path(organization, project),
             params: { signed_id: "invalid_id" },
             headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST upload_export" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "Export Test", platform: "both") }
    let(:valid_png) { "\x89PNG\r\n\x1A\n".b + ("\x00" * 100).b }

    after { FileUtils.rm_rf(project.exports_directory) if project.exports_directory.exist? }

    before do
      Rails.cache.clear
      project.screenshot_scenes.create!(position: 1, source_image_data: "data")
    end

    it "uploads valid PNG screenshots via multipart" do
      file = Rack::Test::UploadedFile.new(
        StringIO.new(valid_png), "image/png", true, original_filename: "shot.png"
      )

      post upload_export_organization_screenshot_project_path(organization, project), params: {
        screenshots: [
          { file: file, width: 1320, height: 2868, scene_position: 1 }
        ]
      }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["data"]["uploaded"]).to eq(1)
      expect(json["data"]["screenshots"].first["resolution"]).to eq("1320x2868")
    end

    it "returns 429 when rate limited" do
      allow(Rails.cache).to receive(:read).with("screenshot_upload:#{user.id}").and_return(true)

      post upload_export_organization_screenshot_project_path(organization, project), params: {
        screenshots: [ { width: 100, height: 100, scene_position: 1, image_data: Base64.encode64(valid_png) } ]
      }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "returns 422 when screenshots param is not a populated array" do
      post upload_export_organization_screenshot_project_path(organization, project),
           params: { screenshots: [ { width: 100, height: 100, scene_position: 1 } ] }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      # Sending a screenshot with no file and no image_data means nothing gets decoded, 0 uploaded
      # To test the empty guard, omit screenshots entirely
      post upload_export_organization_screenshot_project_path(organization, project),
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("Screenshots array")
    end

    it "returns 422 when screenshots param is missing (no params)" do
      post upload_export_organization_screenshot_project_path(organization, project),
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when too many screenshots (>60)" do
      shots = 61.times.map { |i| { width: 100, height: 100, scene_position: i + 1, image_data: Base64.encode64(valid_png) } }

      post upload_export_organization_screenshot_project_path(organization, project), params: { screenshots: shots }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("max 60")
    end

    it "returns 422 when all screenshots have invalid PNG magic bytes" do
      bad_data = Base64.encode64("NOT_A_PNG_FILE")

      post upload_export_organization_screenshot_project_path(organization, project), params: {
        screenshots: [ { width: 100, height: 100, scene_position: 1, image_data: bad_data } ]
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("No valid screenshots")
    end

    it "returns 422 when org export quota is exceeded" do
      allow_any_instance_of(ScreenshotProject).to receive(:org_within_export_quota?).and_return(false)

      post upload_export_organization_screenshot_project_path(organization, project), params: {
        screenshots: [ { width: 100, height: 100, scene_position: 1, image_data: Base64.encode64(valid_png) } ]
      }

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("quota_exhausted")
      expect(json["message"]).to include("quota")
      expect(json["current_plan"]).to eq("pro")
      expect(json["next_plan"]).to eq("team")
      expect(json["suggestion"]).to include("Upgrade from Pro to Team")
    end

    it "returns 422 when all screenshots have invalid dimensions" do
      post upload_export_organization_screenshot_project_path(organization, project), params: {
        screenshots: [ { width: 0, height: 100, scene_position: 1, image_data: Base64.encode64(valid_png) } ]
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("No valid screenshots")
    end

    it "returns 422 when all screenshots have invalid scene position" do
      post upload_export_organization_screenshot_project_path(organization, project), params: {
        screenshots: [ { width: 100, height: 100, scene_position: 0, image_data: Base64.encode64(valid_png) } ]
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("No valid screenshots")
    end

    it "blocks free plans from server-side upload staging" do
      user.update!(plan_tier: :free)

      post upload_export_organization_screenshot_project_path(organization, project), params: {
        screenshots: [
          { width: 1320, height: 2868, scene_position: 1, image_data: Base64.encode64(valid_png) }
        ]
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("plan_upgrade_required")
      expect(json["required_plan"]).to eq("pro")
    end
  end

  describe "POST start_store_upload" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "Store Upload Test", platform: "both") }

    before do
      Rails.cache.clear

      export_dir = project.exports_directory.join("1320x2868")
      FileUtils.mkdir_p(export_dir)
      File.binwrite(export_dir.join("screenshot_01.png"), valid_png_bytes)
    end

    after { FileUtils.rm_rf(project.exports_directory) if project.exports_directory.exist? }

    it "creates a ScreenshotUpload and enqueues a job" do
      expect {
        post start_store_upload_organization_screenshot_project_path(organization, project), params: {
          target: "app_store_connect",
          config: { version_id: "v-123", locale: "en-US" }
        }, headers: { "Accept" => "application/json" }
      }.to change(ScreenshotUpload, :count).by(1)
        .and have_enqueued_job(ScreenshotUploadJob)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["data"]["id"]).to be_present
      expect(json["data"]["status"]).to eq("pending")
    end

    it "defaults locale from project default locale when omitted" do
      project.update!(locales: [ "fr-FR", "en-US" ])

      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "app_store_connect",
        config: { version_id: "v-123" }
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:created)
      upload = ScreenshotUpload.order(:created_at).last
      expect(upload.config["locale"]).to eq("fr-FR")
    end

    it "rejects locale values not in project locales" do
      project.update!(locales: [ "en-US", "fr-FR" ])

      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "app_store_connect",
        config: { version_id: "v-123", locale: "de-DE" }
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("project's locales")
    end

    it "rejects malformed locale values" do
      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "app_store_connect",
        config: { version_id: "v-123", locale: "asdasdasd" }
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("Unsupported locale")
    end

    it "returns 429 when rate limited" do
      allow(Rails.cache).to receive(:read).with("screenshot_store_upload:#{user.id}").and_return(true)

      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "app_store_connect"
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "returns 422 for invalid target" do
      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "invalid_target"
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts app_store_connect target" do
      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "app_store_connect"
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:created)
    end

    it "accepts google_play target" do
      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "google_play"
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:created)
    end

    it "blocks free plans from starting store uploads" do
      user.update!(plan_tier: :free)

      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "app_store_connect"
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("plan_upgrade_required")
      expect(json["required_plan"]).to eq("pro")
    end

    it "returns a quota-style 422 response when the org hits the daily upload cap" do
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

      post start_store_upload_organization_screenshot_project_path(organization, project), params: {
        target: "app_store_connect"
      }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("quota_exhausted")
      expect(json["message"]).to include("Daily upload limit reached")
      expect(json["current_plan"]).to eq("pro")
      expect(json["next_plan"]).to eq("team")
      expect(json["suggestion"]).to include("Upgrade from Pro to Team")
    end
  end

  describe "GET upload_status" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "Status Test", platform: "both") }

    it "returns upload status and progress" do
      upload = ScreenshotUpload.create!(
        screenshot_project: project,
        organization: organization,
        target: "app_store_connect",
        status: "in_progress",
        progress: { "completed" => 3, "total" => 10 }
      )

      get upload_status_organization_screenshot_project_path(organization, project, upload_id: upload.id),
          headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"]["id"]).to eq(upload.id)
      expect(json["data"]["status"]).to eq("in_progress")
      expect(json["data"]["progress"]["completed"]).to eq(3)
    end

    it "returns 404 for non-existent upload" do
      get upload_status_organization_screenshot_project_path(organization, project, upload_id: 0),
          headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET background_image_file" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "BG Image Test", platform: "both") }

    it "redirects to storage proxy when background image is attached" do
      project.background_image.attach(
        io: StringIO.new(valid_png_bytes),
        filename: "bg.png",
        content_type: "image/png"
      )

      get background_image_file_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:redirect)
    end

    it "returns 404 when no background image is attached" do
      get background_image_file_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 and clears attachment when blob file is missing" do
      project.background_image.attach(
        io: StringIO.new(valid_png_bytes),
        filename: "bg-missing.png",
        content_type: "image/png"
      )
      blob = project.background_image.blob
      service = blob.service
      skip "Disk service path_for unavailable" unless service.respond_to?(:path_for)

      FileUtils.rm_f(service.path_for(blob.key))

      get background_image_file_organization_screenshot_project_path(organization, project)

      expect(response).to have_http_status(:not_found)
      expect(project.reload.background_image).not_to be_attached
    end
  end

  describe "GET custom_sticker_image" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "Sticker Image Test", platform: "both") }

    it "redirects to storage proxy for valid attachment_id" do
      project.custom_sticker_images.attach(
        io: StringIO.new(valid_png_bytes),
        filename: "sticker.png",
        content_type: "image/png"
      )
      attachment = project.custom_sticker_images.last

      get custom_sticker_image_organization_screenshot_project_path(organization, project, attachment_id: attachment.id)

      expect(response).to have_http_status(:redirect)
    end

    it "returns 404 for invalid attachment_id" do
      get custom_sticker_image_organization_screenshot_project_path(organization, project, attachment_id: 0)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 and removes attachment when blob file is missing" do
      project.custom_sticker_images.attach(
        io: StringIO.new(valid_png_bytes),
        filename: "sticker-missing.png",
        content_type: "image/png"
      )
      attachment = project.custom_sticker_images.last
      blob = attachment.blob
      service = blob.service
      skip "Disk service path_for unavailable" unless service.respond_to?(:path_for)

      FileUtils.rm_f(service.path_for(blob.key))

      get custom_sticker_image_organization_screenshot_project_path(organization, project, attachment_id: attachment.id)

      expect(response).to have_http_status(:not_found)
      expect(project.reload.custom_sticker_images.attachments.exists?(attachment.id)).to be(false)
    end
  end

  describe "POST upload_background_image" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "BG Upload Test", platform: "both") }

    it "attaches a valid PNG and returns URL" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_image.png"), "image/png")

      post upload_background_image_organization_screenshot_project_path(organization, project),
           params: { file: file },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["url"]).to include("background_image_file")
      expect(project.reload.background_image).to be_attached
    end

    it "returns 422 when file is missing" do
      post upload_background_image_organization_screenshot_project_path(organization, project),
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("File is required")
    end

    it "returns 422 for invalid content type" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_file.txt"), "text/plain")

      post upload_background_image_organization_screenshot_project_path(organization, project),
           params: { file: file },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("PNG, JPEG, or WebP")
    end

    it "returns 422 when file is too large" do
      # Create a tempfile that exceeds the 10MB limit
      large_file = Tempfile.new([ "large", ".png" ])
      large_file.binmode
      large_file.write("\x89PNG\r\n\x1A\n".b)
      large_file.write("\x00" * (10.megabytes + 1))
      large_file.rewind

      upload = Rack::Test::UploadedFile.new(large_file.path, "image/png", true, original_filename: "large.png")

      post upload_background_image_organization_screenshot_project_path(organization, project),
           params: { file: upload },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("10 MB")
    ensure
      large_file.close
      large_file.unlink
    end

    it "returns 422 for invalid magic bytes" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_file.txt"), "image/png")

      post upload_background_image_organization_screenshot_project_path(organization, project),
           params: { file: file },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("valid image format")
    end

    it "uses fresh org media usage instead of stale cached totals" do
      other_project = ScreenshotProject.create!(organization: organization, name: "Other Media", platform: "both")
      other_project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "x" * 200,
        source_image_content_type: "image/png",
        caption_text: "Consumes quota"
      )
      file = Rack::Test::UploadedFile.new(
        StringIO.new(valid_png_bytes), "image/png", true, original_filename: "bg.png"
      )

      Rails.cache.write("org_media_storage:#{organization.id}", 0)
      allow_any_instance_of(ScreenshotProject).to receive(:max_media_storage_bytes_per_organization).and_return(250)

      post upload_background_image_organization_screenshot_project_path(organization, project),
           params: { file: file },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("quota exceeded")
    end

    it "blocks background image uploads when media quota is exhausted but still allows removal" do
      project.background_image.attach(
        io: StringIO.new(valid_png_bytes),
        filename: "existing-bg.png",
        content_type: "image/png"
      )
      other_project = ScreenshotProject.create!(organization: organization, name: "Quota Media", platform: "both")
      other_project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "x" * 200,
        source_image_content_type: "image/png",
        caption_text: "Consumes quota"
      )
      file = Rack::Test::UploadedFile.new(
        StringIO.new(valid_png_bytes), "image/png", true, original_filename: "bg.png"
      )

      allow_any_instance_of(ScreenshotProject).to receive(:max_media_storage_bytes_per_organization).and_return(250)

      post upload_background_image_organization_screenshot_project_path(organization, project),
           params: { file: file },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to include("quota exceeded")

      delete remove_background_image_organization_screenshot_project_path(organization, project),
             headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(project.reload.background_image).not_to be_attached
    end
  end

  describe "DELETE remove_background_image" do
    let(:project) { ScreenshotProject.create!(organization: organization, name: "BG Remove Test", platform: "both") }

    it "purges the attached background image" do
      project.background_image.attach(
        io: StringIO.new(valid_png_bytes),
        filename: "bg.png",
        content_type: "image/png"
      )
      expect(project.background_image).to be_attached

      delete remove_background_image_organization_screenshot_project_path(organization, project),
             headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("ok")
      expect(project.reload.background_image).not_to be_attached
    end

    it "returns ok even when no background image is attached" do
      delete remove_background_image_organization_screenshot_project_path(organization, project),
             headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("ok")
    end
  end

  describe "authorization" do
    it "denies access to non-members" do
      other_user = User.create!(email: "other@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      other_org = Organization.create!(name: "Other Org", owner: other_user)

      get organization_screenshot_projects_path(other_org)
      # set_org now scopes the lookup to current_user.organizations, so a
      # non-member sees 404 — same response as a non-existent id, which
      # closes the enumeration oracle (302 = exists but not mine; 404 =
      # doesn't exist). See OrganizationsController#set_organization.
      expect(response).to have_http_status(:not_found)
    end
  end

  private

  def valid_png_bytes
    "\x89PNG\r\n\x1A\n".b + ("\x00" * 100).b
  end
end
