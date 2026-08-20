require "rails_helper"

RSpec.describe ReleaseNoteRewriteJob, type: :job do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:release_note) { create(:release_note, organization: organization, listable: apple_app) }
  let(:raw_input) { "fix: crash on startup\nfeat: dark mode" }

  let(:mock_rewriter) { instance_double(ReleaseNotes::AiRewriter) }

  before do
    # Pre-set the reset timestamp to avoid dirty attributes from monthly reset logic
    organization.update_columns(ai_rewrites_count: 0, ai_rewrites_reset_at: Time.current)
    allow(ReleaseNotes::AiRewriter).to receive(:new).and_return(mock_rewriter)
    allow(mock_rewriter).to receive(:rewrite!).and_return({
      "new" => [ "Dark mode" ],
      "fixed" => [ "Crash on startup" ],
      "rendered_text" => "NEW\n- Dark mode\n\nFIXED\n- Crash on startup"
    })
  end

  describe "#perform" do
    it "calls AiRewriter when quota is available" do
      described_class.perform_now(
        organization_id: organization.id,
        release_note_id: release_note.id,
        raw_input: raw_input
      )

      expect(ReleaseNotes::AiRewriter).to have_received(:new).with(
        release_note: release_note,
        raw_input: raw_input
      )
      expect(mock_rewriter).to have_received(:rewrite!)
    end

    it "increments ai_rewrites_count on success" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id,
          raw_input: raw_input
        )
      }.to change { organization.reload.ai_rewrites_count }.by(1)
    end

    it "skips when no quota remaining" do
      # Exhaust quota
      organization.update_columns(ai_rewrites_count: 50, ai_rewrites_reset_at: Time.current)

      described_class.perform_now(
        organization_id: organization.id,
        release_note_id: release_note.id,
        raw_input: raw_input
      )

      expect(ReleaseNotes::AiRewriter).not_to have_received(:new)
    end

    it "does not increment counter when quota exhausted" do
      organization.update_columns(ai_rewrites_count: 50, ai_rewrites_reset_at: Time.current)

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id,
          raw_input: raw_input
        )
      }.not_to change { organization.reload.ai_rewrites_count }
    end

    it "refunds quota on rewriter failure" do
      allow(mock_rewriter).to receive(:rewrite!).and_raise(StandardError, "API error")
      initial_count = organization.ai_rewrites_count

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id,
          raw_input: raw_input
        )
      }.to raise_error(StandardError)

      # Counter was incremented then decremented, net zero change
      expect(organization.reload.ai_rewrites_count).to eq(initial_count)
    end

    it "returns silently when organization not found" do
      expect {
        described_class.perform_now(
          organization_id: -1,
          release_note_id: release_note.id,
          raw_input: raw_input
        )
      }.not_to raise_error

      expect(ReleaseNotes::AiRewriter).not_to have_received(:new)
    end

    it "returns silently when release note not found" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: -1,
          raw_input: raw_input
        )
      }.not_to raise_error

      expect(ReleaseNotes::AiRewriter).not_to have_received(:new)
    end

    it "enqueues the job" do
      expect {
        described_class.perform_later(
          organization_id: organization.id,
          release_note_id: release_note.id,
          raw_input: raw_input
        )
      }.to have_enqueued_job(described_class)
    end
  end
end
