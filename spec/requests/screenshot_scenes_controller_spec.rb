require "rails_helper"

RSpec.describe "ScreenshotScenesController", type: :request do
  def stub_thumbnail_variant_processing(result = true, error: nil)
    [ ActiveStorage::Variant, ActiveStorage::VariantWithRecord ].each do |klass|
      next unless defined?(klass)

      if error
        allow_any_instance_of(klass).to receive(:processed).and_raise(error)
      else
        allow_any_instance_of(klass).to receive(:processed).and_return(result)
      end
    end
  end

  let(:user) { User.create!(email: "scenedev@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro, onboarding_completed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }
  let(:project) { ScreenshotProject.create!(organization: organization, name: "Test Project", platform: "both") }

  before do
    sign_in user, scope: :user
  end

  describe "POST /organizations/:org_id/screenshot_projects/:project_id/screenshot_scenes" do
    it "creates a scene from an uploaded file" do
      file = Tempfile.new([ "screenshot", ".png" ])
      file.binmode
      # Write valid PNG magic bytes followed by minimal data
      file.write("\x89PNG\r\n\x1A\n".b + ("x" * 100).b)
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "screen1.png")

      expect {
        post organization_screenshot_project_screenshot_scenes_path(organization, project), params: {
          screenshot_scene: { file: upload }
        }
      }.to change(ScreenshotScene, :count).by(1)

      scene = ScreenshotScene.last
      expect(scene.source_image_content_type).to eq("image/png")
      expect(scene.screenshot_project).to eq(project)
      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
    ensure
      file.close
      file.unlink
    end

    it "redirects with alert when no files are provided" do
      post organization_screenshot_project_screenshot_scenes_path(organization, project), params: {
        screenshot_scene: { file: nil }
      }
      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
      expect(flash[:alert]).to include("No files")
    end

    it "blocks new scene uploads when media quota is exhausted but still allows deletes" do
      other_project = ScreenshotProject.create!(organization: organization, name: "Quota Media", platform: "both")
      other_project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "x" * 200,
        source_image_content_type: "image/png",
        caption_text: "Consumes quota"
      )
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "Keep me")
      file = Tempfile.new([ "screenshot", ".png" ])
      file.binmode
      file.write("\x89PNG\r\n\x1A\n".b + ("x" * 100).b)
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "blocked.png")

      allow_any_instance_of(ScreenshotProject).to receive(:max_media_storage_bytes_per_organization).and_return(250)

      expect {
        post organization_screenshot_project_screenshot_scenes_path(organization, project), params: {
          screenshot_scene: { file: upload }
        }
      }.not_to change(ScreenshotScene, :count)

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
      expect(flash[:alert]).to include("quota")

      expect {
        delete organization_screenshot_project_screenshot_scene_path(organization, project, scene)
      }.to change(ScreenshotScene, :count).by(-1)

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
      expect(project.reload.screenshot_scenes.pluck(:caption_text)).not_to include("Keep me")
    ensure
      file.close
      file.unlink
    end
  end

  describe "PATCH /organizations/:org_id/screenshot_projects/:project_id/screenshot_scenes/:id" do
    it "updates the caption text" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "Old")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene), params: {
        screenshot_scene: { caption_text: "New Caption" }
      }

      scene.reload
      expect(scene.caption_text).to eq("New Caption")
    end

    it "returns JSON for AJAX requests" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "Old")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { caption_text: "Updated" } },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to eq(true)
    end

    it "updates the subtitle text" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", subtitle_text: "Old Sub")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { subtitle_text: "New Subtitle" } },
            headers: { "Accept" => "application/json" }

      scene.reload
      expect(scene.subtitle_text).to eq("New Subtitle")
    end

    it "persists overrides" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { caption_color: "#FF0000" } } },
            headers: { "Accept" => "application/json" }

      scene.reload
      expect(scene.overrides).to eq({ "caption_color" => "#FF0000" })
    end

    it "persists drag position overrides" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { text_position_x: "45.5", text_position_y: "30.2" } } },
            headers: { "Accept" => "application/json" }

      scene.reload
      expect(scene.overrides["text_position_x"]).to eq("45.5")
      expect(scene.overrides["text_position_y"]).to eq("30.2")
      expect(scene.custom_text_position?).to be true
    end

    it "persists drag position overrides via JSON" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { text_position_x: 45.5, text_position_y: 30.2 } } },
            as: :json

      scene.reload
      expect(scene.overrides["text_position_x"]).to eq(45.5)
      expect(scene.overrides["text_position_y"]).to eq(30.2)
    end

    it "persists custom_image stickers in overrides" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      stickers = [
        { type: "custom_image", image_url: "/rails/active_storage/blobs/test123/logo.png", x: 50, y: 50, size: 96, rotation: 0 }
      ]

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { stickers: stickers } } },
            as: :json

      scene.reload
      expect(scene.overrides["stickers"]).to be_present
      expect(scene.overrides["stickers"].first["type"]).to eq("custom_image")
      expect(scene.overrides["stickers"].first["image_url"]).to be_present
    end

    it "persists subtitle_font_size overrides" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { subtitle_font_size: 28 } } },
            as: :json

      scene.reload
      expect(scene.overrides["subtitle_font_size"]).to eq(28)
    end
  end

  describe "DELETE /organizations/:org_id/screenshot_projects/:project_id/screenshot_scenes/:id" do
    it "deletes the scene" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      expect {
        delete organization_screenshot_project_screenshot_scene_path(organization, project, scene)
      }.to change(ScreenshotScene, :count).by(-1)

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
    end
  end

  describe "GET /organizations/:org_id/screenshot_projects/:project_id/screenshot_scenes/:id/image" do
    it "serves an ActiveStorage-backed scene image" do
      scene = project.screenshot_scenes.new(
        position: 1,
        source_image_content_type: "image/png",
        source_image_filename: "attached.png"
      )
      scene.source_image.attach(
        io: StringIO.new("attached_png_binary"),
        filename: "attached.png",
        content_type: "image/png"
      )
      scene.save!

      get image_organization_screenshot_project_screenshot_scene_path(organization, project, scene)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("image/png")
      expect(response.body).to eq("attached_png_binary")
    end

    it "serves the image data" do
      scene = project.screenshot_scenes.create!(
        position: 1,
        source_image_data: "fake_png_binary",
        source_image_content_type: "image/png",
        source_image_filename: "test.png"
      )

      get image_organization_screenshot_project_screenshot_scene_path(organization, project, scene)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("image/png")
      expect(response.body).to eq("fake_png_binary")
    end

    it "returns 404 when image data is missing" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")
      scene.update_column(:source_image_data, nil)

      get image_organization_screenshot_project_screenshot_scene_path(organization, project, scene)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /organizations/:org_id/screenshot_projects/:project_id/screenshot_scenes/:id/thumbnail" do
    it "redirects to a proxy representation for attached images" do
      scene = project.screenshot_scenes.new(
        position: 1,
        source_image_content_type: "image/png",
        source_image_filename: "thumb.png"
      )
      scene.source_image.attach(
        io: StringIO.new(File.binread(Rails.root.join("spec/fixtures/files/test_image.png"))),
        filename: "thumb.png",
        content_type: "image/png"
      )
      scene.save!

      stub_thumbnail_variant_processing

      get thumbnail_organization_screenshot_project_screenshot_scene_path(organization, project, scene)

      expect(response).to have_http_status(:found)
      expect(response.location).to include("/rails/active_storage/representations/proxy/")
    end

    it "falls back to the original image when variant processing is unavailable" do
      scene = project.screenshot_scenes.new(
        position: 1,
        source_image_content_type: "image/png",
        source_image_filename: "thumb.png"
      )
      scene.source_image.attach(
        io: StringIO.new(File.binread(Rails.root.join("spec/fixtures/files/test_image.png"))),
        filename: "thumb.png",
        content_type: "image/png"
      )
      scene.save!

      stub_thumbnail_variant_processing(error: LoadError.new("Could not open library 'vips.42'"))

      get thumbnail_organization_screenshot_project_screenshot_scene_path(organization, project, scene)

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(image_organization_screenshot_project_screenshot_scene_path(organization, project, scene))
    end
  end

  describe "POST /organizations/:org_id/screenshot_projects/:project_id/screenshot_scenes/reorder" do
    it "updates positions for all scenes" do
      scene1 = project.screenshot_scenes.create!(position: 1, source_image_data: "data1")
      scene2 = project.screenshot_scenes.create!(position: 2, source_image_data: "data2")

      post reorder_organization_screenshot_project_screenshot_scenes_path(organization, project),
           params: { positions: [ { id: scene1.id, position: 2 }, { id: scene2.id, position: 1 } ] },
           as: :json

      scene1.reload
      scene2.reload
      expect(scene1.position).to eq(2)
      expect(scene2.position).to eq(1)
    end
  end

  describe "POST /organizations/:org_id/screenshot_projects/:project_id/screenshot_scenes/:id/copy" do
    it "copies a scene to another project" do
      target_project = ScreenshotProject.create!(organization: organization, name: "Target", platform: "both")
      scene = project.screenshot_scenes.create!(
        position: 1, source_image_data: "data",
        caption_text: "Copy Me", subtitle_text: "Sub",
        overrides: { "caption_color" => "#FF0000" }
      )

      expect {
        post copy_organization_screenshot_project_screenshot_scene_path(organization, project, scene),
             params: { target_project_id: target_project.id }
      }.to change(ScreenshotScene, :count).by(1)

      new_scene = target_project.screenshot_scenes.last
      expect(new_scene.caption_text).to eq("Copy Me")
      expect(new_scene.subtitle_text).to eq("Sub")
      expect(new_scene.overrides).to eq({ "caption_color" => "#FF0000" })
      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
      expect(flash[:notice]).to include("copied")
    end

    it "copies locale_variants to the target scene" do
      target_project = ScreenshotProject.create!(organization: organization, name: "Target", platform: "both")
      scene = project.screenshot_scenes.create!(
        position: 1, source_image_data: "data",
        caption_text: "English",
        locale_variants: { "de-DE" => { "caption_text" => "Deutsch" } }
      )

      post copy_organization_screenshot_project_screenshot_scene_path(organization, project, scene),
           params: { target_project_id: target_project.id }

      new_scene = target_project.screenshot_scenes.last
      expect(new_scene.locale_variants).to eq({ "de-DE" => { "caption_text" => "Deutsch" } })
    end

    it "returns JSON success for AJAX copy" do
      target_project = ScreenshotProject.create!(organization: organization, name: "Target", platform: "both")
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "Copy")

      post copy_organization_screenshot_project_screenshot_scene_path(organization, project, scene),
           params: { target_project_id: target_project.id },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["scene_id"]).to be_present
    end

    it "fails when target project is at scene limit" do
      target_project = ScreenshotProject.create!(organization: organization, name: "Full Target", platform: "both")
      target_project.max_screenshot_scenes_per_project.times do |i|
        target_project.screenshot_scenes.create!(source_image_data: "data#{i}", position: i + 1)
      end

      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "Won't fit")

      expect {
        post copy_organization_screenshot_project_screenshot_scene_path(organization, project, scene),
             params: { target_project_id: target_project.id }
      }.not_to change(ScreenshotScene, :count)

      expect(response).to redirect_to(editor_organization_screenshot_project_path(organization, project))
      expect(flash[:alert]).to include("Failed")
    end
  end

  describe "PATCH /organizations/:org_id/screenshot_projects/:project_id/screenshot_scenes/bulk_update" do
    it "updates multiple scenes at once" do
      scene1 = project.screenshot_scenes.create!(position: 1, source_image_data: "data1", caption_text: "Old 1")
      scene2 = project.screenshot_scenes.create!(position: 2, source_image_data: "data2", caption_text: "Old 2")

      patch bulk_update_organization_screenshot_project_screenshot_scenes_path(organization, project),
            params: {
              scenes: [
                { id: scene1.id, caption_text: "New 1", subtitle_text: "Sub 1" },
                { id: scene2.id, caption_text: "New 2", subtitle_text: "Sub 2" }
              ]
            },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true

      scene1.reload
      scene2.reload
      expect(scene1.caption_text).to eq("New 1")
      expect(scene1.subtitle_text).to eq("Sub 1")
      expect(scene2.caption_text).to eq("New 2")
      expect(scene2.subtitle_text).to eq("Sub 2")
    end

    it "updates locale_variants through bulk update" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "English")

      patch bulk_update_organization_screenshot_project_screenshot_scenes_path(organization, project),
            params: {
              scenes: [
                {
                  id: scene.id,
                  caption_text: "English",
                  subtitle_text: "Sub",
                  locale_variants: { "de-DE" => { "caption_text" => "Deutsch", "subtitle_text" => "Unter" } }
                }
              ]
            },
            as: :json

      expect(response).to have_http_status(:ok)
      scene.reload
      expect(scene.locale_variants["de-DE"]["caption_text"]).to eq("Deutsch")
      expect(scene.locale_variants["de-DE"]["subtitle_text"]).to eq("Unter")
    end

    it "skips scenes not belonging to the project" do
      other_project = ScreenshotProject.create!(organization: organization, name: "Other", platform: "both")
      other_scene = other_project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "Don't touch")

      patch bulk_update_organization_screenshot_project_screenshot_scenes_path(organization, project),
            params: {
              scenes: [
                { id: other_scene.id, caption_text: "Hacked" }
              ]
            },
            as: :json

      other_scene.reload
      expect(other_scene.caption_text).to eq("Don't touch")
    end
  end

  describe "PATCH update with locale_variants" do
    it "persists locale_variants on a scene" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "English")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: {
              screenshot_scene: {
                caption_text: "English",
                locale_variants: { "de-DE" => { "caption_text" => "Deutsch" } }
              }
            },
            as: :json

      expect(response).to have_http_status(:ok)
      scene.reload
      expect(scene.locale_variants["de-DE"]["caption_text"]).to eq("Deutsch")
    end
  end

  describe "sanitize_overrides" do
    it "strips disallowed override keys" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { caption_color: "#FF0000", background_color: "#000", hacky_key: "evil", definitely_not_allowed: "nope" } } },
            as: :json

      scene.reload
      expect(scene.overrides).to have_key("caption_color")
      expect(scene.overrides).to have_key("background_color")
      expect(scene.overrides).not_to have_key("hacky_key")
      expect(scene.overrides).not_to have_key("definitely_not_allowed")
    end

    it "clamps sticker x/y to 0-100" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { stickers: [
              { type: "emoji", emoji: "🔥", x: -10, y: 200, size: 50, rotation: 0 }
            ] } } },
            as: :json

      scene.reload
      sticker = scene.overrides["stickers"].first
      expect(sticker["x"]).to eq(0)
      expect(sticker["y"]).to eq(100)
    end

    it "clamps sticker size to 10-500" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { stickers: [
              { type: "emoji", emoji: "🔥", x: 50, y: 50, size: 5, rotation: 0 },
              { type: "emoji", emoji: "⭐", x: 50, y: 50, size: 999, rotation: 0 }
            ] } } },
            as: :json

      scene.reload
      expect(scene.overrides["stickers"][0]["size"]).to eq(10)
      expect(scene.overrides["stickers"][1]["size"]).to eq(500)
    end

    it "clamps sticker rotation to -180..180" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { stickers: [
              { type: "emoji", emoji: "🔥", x: 50, y: 50, size: 50, rotation: -270 }
            ] } } },
            as: :json

      scene.reload
      expect(scene.overrides["stickers"].first["rotation"]).to eq(-180)
    end

    it "truncates sticker emoji to 20 chars and text to 200 chars" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { stickers: [
              { type: "emoji", emoji: "🔥" * 30, text: "A" * 300, x: 50, y: 50, size: 50, rotation: 0 }
            ] } } },
            as: :json

      scene.reload
      sticker = scene.overrides["stickers"].first
      expect(sticker["emoji"].length).to be <= 21
      expect(sticker["text"].length).to be <= 201
    end

    it "filters out stickers with no emoji, invalid asset_key, or wrong type" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { stickers: [
              { type: "emoji", emoji: "", x: 50, y: 50, size: 50, rotation: 0 },
              { type: "asset", asset_key: "nonexistent_key", x: 50, y: 50, size: 50, rotation: 0 },
              { type: "other", x: 50, y: 50, size: 50, rotation: 0 },
              { type: "emoji", emoji: "🔥", x: 50, y: 50, size: 50, rotation: 0 }
            ] } } },
            as: :json

      scene.reload
      expect(scene.overrides["stickers"].length).to eq(1)
      expect(scene.overrides["stickers"].first["emoji"]).to eq("🔥")
    end

    it "limits stickers to MAX_STICKERS_PER_SCENE (20)" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      stickers = 25.times.map do |i|
        { type: "emoji", emoji: "🔥", x: i * 3, y: i * 3, size: 50, rotation: 0 }
      end

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { overrides: { stickers: stickers } } },
            as: :json

      scene.reload
      expect(scene.overrides["stickers"].length).to eq(20)
    end
  end

  describe "sanitize_locale_variants" do
    it "rejects invalid locale format" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "English")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: {
              screenshot_scene: {
                caption_text: "English",
                locale_variants: { "invalid!!" => { "caption_text" => "Bad" }, "de-DE" => { "caption_text" => "Deutsch" } }
              }
            },
            as: :json

      scene.reload
      expect(scene.locale_variants).to have_key("de-DE")
      expect(scene.locale_variants).not_to have_key("invalid!!")
    end

    it "truncates text to 500 chars" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "English")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: {
              screenshot_scene: {
                caption_text: "English",
                locale_variants: { "de-DE" => { "caption_text" => "A" * 600 } }
              }
            },
            as: :json

      scene.reload
      expect(scene.locale_variants["de-DE"]["caption_text"].length).to eq(500)
    end

    it "limits to 50 locale entries" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "English")

      variants = {}
      55.times do |i|
        locale = "xx-#{i.to_s.rjust(2, '0')}"
        # only valid format locales
        locale = "xx-#{('AA'..'ZZ').to_a[i]}" if i < 55
        variants[locale] = { "caption_text" => "Text #{i}" }
      end

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: { screenshot_scene: { caption_text: "English", locale_variants: variants } },
            as: :json

      scene.reload
      expect(scene.locale_variants.size).to be <= 50
    end

    it "filters to only allowed keys (caption_text, subtitle_text)" do
      scene = project.screenshot_scenes.create!(position: 1, source_image_data: "data", caption_text: "English")

      patch organization_screenshot_project_screenshot_scene_path(organization, project, scene),
            params: {
              screenshot_scene: {
                caption_text: "English",
                locale_variants: { "de-DE" => { "caption_text" => "Deutsch", "evil_key" => "bad", "subtitle_text" => "Unter" } }
              }
            },
            as: :json

      scene.reload
      expect(scene.locale_variants["de-DE"]).to have_key("caption_text")
      expect(scene.locale_variants["de-DE"]).to have_key("subtitle_text")
      expect(scene.locale_variants["de-DE"]).not_to have_key("evil_key")
    end
  end

  describe "authorization" do
    it "denies access to non-members" do
      other_user = User.create!(email: "other@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      other_org = Organization.create!(name: "Other Org", owner: other_user)
      other_project = ScreenshotProject.create!(organization: other_org, name: "Other", platform: "both")
      scene = other_project.screenshot_scenes.create!(position: 1, source_image_data: "data")

      get image_organization_screenshot_project_screenshot_scene_path(other_org, other_project, scene)
      # set_org now scopes the lookup to current_user.organizations, so a
      # non-member sees 404 — same response as a non-existent id, which
      # closes the enumeration oracle (302 = exists but not mine; 404 =
      # doesn't exist). See OrganizationsController#set_organization.
      expect(response).to have_http_status(:not_found)
    end
  end
end
