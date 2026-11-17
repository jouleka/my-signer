require "rails_helper"

RSpec.describe "Release workflow regressions", type: :request do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:release_id) { "apple_app_#{apple_app.id}" }
  let!(:note) { create(:release_note, organization: organization, listable: apple_app, version_string: "2.0.0") }
  before { sign_in user }

  it "rejects notes from a different app within the same organization" do
    other_app = create(:apple_app, organization: organization, sku: "other-app")
    patch update_release_translation_organization_release_path(organization, "apple_app_#{other_app.id}", note_id: note.id, locale: "de-DE"),
      params: { locale: "de-DE", translated_text: "Wrong app" }, as: :turbo_stream
    expect(response).to have_http_status(:not_found)
    expect(note.reload.translations).to be_empty
  end

  it "rejects changes to content while it is awaiting review" do
    organization.memberships.create!(user: create(:user), role: :developer)
    note.submit_for_review!(user: user)
    patch update_release_note_organization_release_path(organization, release_id, note_id: note.id),
      params: { release_note: { rendered_text: "Changed after submission" } }, as: :turbo_stream
    expect(response).to have_http_status(:forbidden)
    expect(note.reload.rendered_text).not_to eq("Changed after submission")
  end

  it "returns actionable translation length errors without saving" do
    patch update_release_translation_organization_release_path(organization, release_id, note_id: note.id, locale: "de-DE"),
      params: { locale: "de-DE", translated_text: "x" * 4001 }, as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["errors"].join).to include("4000")
    expect(note.reload.translations).to be_empty
  end

  it "rejects malformed template JSON instead of reporting a successful save" do
    patch update_release_note_organization_release_path(organization, release_id, note_id: note.id),
      params: { release_note: { template_data: "{broken" } }, as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "creates a fresh checklist and note empty state for a new version" do
    old_checklist = create(:release_checklist, :all_checked, organization: organization, listable: apple_app, version_string: "1.0.0")
    get organization_release_path(organization, release_id, tab: "whats_new", version_string: "3.0.0")
    expect(response.body).to include("No release notes yet")
    expect(organization.release_checklists.for_app(apple_app).find_by(version_string: "3.0.0")).to be_present
    expect(old_checklist.reload.all_required_complete).to be(true)
  end

  it "can create the first note before a store version has been synced" do
    note.destroy!
    post create_release_note_organization_release_path(organization, release_id), params: { release_note: { version_string: "", locale: "en-US" } }
    follow_redirect!
    expect(response.body).to include("release-note-editor")
    expect(organization.release_notes.last.version_string).to be_blank
  end

  it "queues only one AI operation and retains an enqueue failure for retry" do
    path = rewrite_release_note_organization_release_path(organization, release_id, note_id: note.id)
    expect {
      2.times { post path, params: { raw_input: "Fix search" } }
    }.to have_enqueued_job(ReleaseNoteRewriteJob).exactly(:once)
    expect(note.reload).to be_ai_pending
    operation = ReleaseNotes::OperationStatus.new(note)
    operation.finish!(note.metadata.dig("ai_operation", "id"), error: "Worker unavailable")
    allow(ReleaseNoteRewriteJob).to receive(:perform_later).and_raise("Queue unavailable")
    post path, params: { raw_input: "Try again" }, as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_content)
    expect(note.reload).not_to be_ai_pending
    expect(note.metadata.dig("ai_operation", "error")).to include("Queue unavailable")
  end

  it "rejects an unknown checklist item and a checklist belonging to another app" do
    checklist = create(:release_checklist, organization: organization, listable: apple_app)
    post check_item_organization_release_release_checklist_path(organization, release_id, checklist), params: { key: "missing" }, as: :json
    expect(response).to have_http_status(:not_found)
    post check_item_organization_release_release_checklist_path(organization, "android_app_1", checklist), params: { key: "build_tested" }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(checklist.reload.items.any? { |item| item["checked"] }).to be(false)
  end

  it "does not block the current release with validation errors from an old version" do
    old = create(:app_store_version, organization: organization, apple_app: apple_app, version_string: "1.0.0", issues: [ { "code" => "OLD_FAILURE", "detail" => "Old error" } ])
    create(:app_store_version, organization: organization, apple_app: apple_app, version_string: "2.0.0")
    checklist = create(:release_checklist, organization: organization, listable: apple_app, version_string: "2.0.0")
    expect(checklist.auto_detected_items.pluck("key")).not_to include("auto_ios_validation_#{old.id}_OLD_FAILURE")
  end
end
