require "rails_helper"

RSpec.describe "Custom Product Page uploads from staged exports", type: :request do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let!(:credential) { create(:app_store_connect_credential, organization: organization) }
  let(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }
  let(:version) { create(:custom_product_page_version, custom_product_page: cpp) }
  let!(:localization) { create(:custom_product_page_localization, custom_product_page_version: version, locale: "de-DE") }
  let(:project) { create(:screenshot_project, organization: organization) }
  let(:png) { file_fixture("studio_screen.png").binread }

  before { sign_in user, scope: :user }

  def upload!(presets: [ "ios_required" ])
    post upload_screenshots_organization_custom_product_page_path(organization, cpp),
      params: { screenshot_project_id: project.id, cpp_localization_id: localization.remote_id, presets: presets }, as: :json
  end

  it "accepts presets staged by Studio in ActiveStorage (no disk exports) and records the localization locale" do
    ScreenshotExport.upsert_export!(project: project, resolution: "1320x2868", scene_position: 1, locale: "de-DE", image_data: png)
    expect(project.exports_directory).not_to exist

    expect { upload! }.to have_enqueued_job(ScreenshotUploadJob)
    expect(response).to have_http_status(:created)
    expect(ScreenshotUpload.last.config).to include("locale" => "de-DE", "cpp_localization_id" => localization.remote_id)
  end

  it "accepts flat (unlocalized) staged exports" do
    ScreenshotExport.upsert_export!(project: project, resolution: "1290x2796", scene_position: 1, image_data: png)
    upload!
    expect(response).to have_http_status(:created)
  end

  it "reports a preset missing when only another locale was staged" do
    ScreenshotExport.upsert_export!(project: project, resolution: "1320x2868", scene_position: 1, locale: "fr-FR", image_data: png)
    expect { upload! }.not_to have_enqueued_job(ScreenshotUploadJob)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to include("iPhone Required")
  end

  it "reports presets with no staged exports at all" do
    upload!(presets: [ "ios_ipad" ])
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to include("iPad")
  end
end
