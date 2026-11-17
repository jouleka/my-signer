require "rails_helper"

RSpec.describe "Release state integrity", type: :model do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:app) { create(:apple_app, organization: organization) }
  let(:note) { create(:release_note, organization: organization, listable: app) }

  it "records approval independently from the reviewer's comment" do
    note.submit_for_review!(user: user)
    note.approve_review!(user: user, comment: "Looks good, thanks")
    expect(note.reload).to be_approved
    expect(note).not_to be_rejected
  end

  it "invalidates approval when content changes and requires another review" do
    organization.memberships.create!(user: create(:user), role: :developer)
    note.submit_for_review!(user: user)
    note.approve_review!(user: user)
    note.update!(rendered_text: "Changed after approval")
    expect(note.reload).not_to be_approved
    expect(note).to be_review_required
    expect { note.apply_to_store_listings! }.to raise_error(/needs approval/)
    note.submit_for_review!(user: user)
    expect(note.reviewed_at).to be_nil
    expect(note.review_comment).to be_nil
  end

  it "prevents two reviewers from deciding the same submitted state" do
    note.submit_for_review!(user: user)
    stale_copy = ReleaseNote.find(note.id)
    note.approve_review!(user: user)
    expect { stale_copy.reject_review!(user: user, comment: "Too late") }.to raise_error(/not pending_review/)
    expect(note.reload).to be_approved
  end

  it "validates generated template length before saving" do
    note.assign_attributes(template_data: { "new" => [ "x" * 4000 ] }, rendered_text: "")
    expect(note.save).to be(false)
    expect(note.errors.full_messages.join).to include("maximum is 4000")
  end

  it "rejects JSON template values that would crash the editor" do
    [ nil, [], "text", false ].each do |invalid|
      note.template_data = invalid
      expect(note).not_to be_valid
      expect(note.errors[:template_data]).to be_present
    end
  end

  it "returns edited applied notes to draft so they can be applied again" do
    create(:store_listing, organization: organization, listable: app, locale: "en-US")
    note.apply_to_store_listings!
    note.update!(rendered_text: "New wording")
    expect(note.reload.status).to eq("draft")
    expect(note.applied_at).to be_nil
  end

  it "rolls back all listing changes if a translation has no matching listing" do
    listing = create(:store_listing, organization: organization, listable: app, locale: "en-US", whats_new: "Keep this")
    note.update!(translations: { "de-DE" => "Nicht verlieren" })
    expect { note.apply_to_store_listings! }.to raise_error(/Create a store listing for de-DE/)
    expect(listing.reload.whats_new).to eq("Keep this")
    expect(note.reload.status).to eq("draft")
  end

  it "does not lose a checklist item changed by another session" do
    checklist = create(:release_checklist, organization: organization, listable: app)
    stale_copy = ReleaseChecklist.find(checklist.id)
    checklist.check_item!("release_notes_written", user)
    stale_copy.check_item!("build_tested", user)
    expect(checklist.reload.items.select { |item| item["checked"] }.pluck("key")).to contain_exactly("release_notes_written", "build_tested")
  end

  it "resets custom items along with the defaults" do
    checklist = create(:release_checklist, :all_checked, organization: organization, listable: app)
    checklist.add_custom_item!(label: "Legal signoff", required: true)
    checklist.check_item!(checklist.custom_items.first["key"], user)
    checklist.reset_items!
    expect((checklist.reload.items + checklist.custom_items).any? { |item| item["checked"] }).to be(false)
  end

  it "never displays ready while a required detected issue is unresolved" do
    checklist = create(:release_checklist, :all_checked, organization: organization, listable: app)
    allow(checklist).to receive(:auto_detected_items).and_return([ { "required" => true, "severity" => "error" } ])
    expect(checklist).not_to be_ready_for_submission
  end
end
