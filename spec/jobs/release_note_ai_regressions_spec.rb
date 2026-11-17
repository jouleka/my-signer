require "rails_helper"

RSpec.describe "Release note AI integrity", type: :job do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:app) { create(:apple_app, organization: organization) }
  let(:note) { create(:release_note, organization: organization, listable: app, template_data: {}, rendered_text: "Original") }
  let!(:listing) { create(:store_listing, organization: organization, listable: app, locale: "de-DE") }
  let(:client) { instance_double(OpenAI::Client) }

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("test-key")
    allow(OpenAI::Client).to receive(:new).and_return(client)
    organization.update_columns(ai_translations_reset_at: Time.current, ai_rewrites_reset_at: Time.current)
  end

  def response_for(text)
    { "choices" => [ { "message" => { "content" => { translated_text: text }.to_json } } ] }
  end

  [ nil, "", [ "bad shape" ], "x" * 4001 ].each_with_index do |invalid, index|
    it "refunds quota and exposes invalid translation response #{index + 1}" do
      id = ReleaseNotes::OperationStatus.new(note).start!("translation")
      allow(client).to receive(:chat).and_return(response_for(invalid))
      ReleaseNoteTranslationJob.perform_now(organization_id: organization.id, release_note_id: note.id, operation_id: id)
      expect(note.reload.translations).to be_empty
      expect(note.metadata.dig("ai_operation", "status")).to eq("failed")
      expect(organization.reload.ai_translations_count).to eq(0)
    end
  end

  it "does not charge a duplicate delivery or replace a manual edit made during translation" do
    id = ReleaseNotes::OperationStatus.new(note).start!("translation")
    allow(client).to receive(:chat) do
      ReleaseNote.find(note.id).update!(translations: { "de-DE" => "Manual edit" })
      response_for("Old AI result")
    end
    expect {
      ReleaseNoteTranslationJob.perform_now(organization_id: organization.id, release_note_id: note.id, operation_id: id)
    }.to raise_error(/changed while translating/)
    expect(note.reload.translations["de-DE"]).to eq("Manual edit")
    expect(organization.reload.ai_translations_count).to eq(0)
    ReleaseNoteTranslationJob.perform_now(organization_id: organization.id, release_note_id: note.id, operation_id: id)
    expect(client).to have_received(:chat).once
  end

  it "keeps saved translations charged if the refresh broadcast fails" do
    id = ReleaseNotes::OperationStatus.new(note).start!("translation")
    allow(client).to receive(:chat).and_return(response_for("Gespeichert"))
    allow_any_instance_of(ReleaseNote).to receive(:trigger_live_refresh).and_raise("Cable down")
    ReleaseNoteTranslationJob.perform_now(organization_id: organization.id, release_note_id: note.id, operation_id: id)
    expect(note.reload.translations["de-DE"]).to eq("Gespeichert")
    expect(organization.reload.ai_translations_count).to eq(1)
    expect(note.metadata.dig("ai_operation", "status")).to eq("completed")
  end

  it "rejects stale rewrites and refunds their quota" do
    allow(client).to receive(:chat) do
      ReleaseNote.find(note.id).update!(rendered_text: "Manual correction")
      { "choices" => [ { "message" => { "content" => { rendered_text: "Stale rewrite" }.to_json } } ] }
    end
    expect {
      ReleaseNoteRewriteJob.perform_now(organization_id: organization.id, release_note_id: note.id, raw_input: "Changes")
    }.to raise_error(/changed while rewriting/)
    expect(note.reload.rendered_text).to eq("Manual correction")
    expect(organization.reload.ai_rewrites_count).to eq(0)
  end

  [ "x" * 4001, [ "invalid text" ] ].each_with_index do |invalid, index|
    it "recovers from invalid rewrite response #{index + 1} with a visible failure and refunded quota" do
      id = ReleaseNotes::OperationStatus.new(note).start!("rewrite")
      allow(client).to receive(:chat).and_return("choices" => [ { "message" => { "content" => { rendered_text: invalid }.to_json } } ])
      expect {
        ReleaseNoteRewriteJob.perform_now(organization_id: organization.id, release_note_id: note.id, raw_input: "Fix search", operation_id: id)
      }.to raise_error(StandardError)
      expect(note.reload.rendered_text).to eq("Original")
      expect(note.metadata.dig("ai_operation", "status")).to eq("failed")
      expect(organization.reload.ai_rewrites_count).to eq(0)
    end
  end
end
