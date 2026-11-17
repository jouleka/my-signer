require "rails_helper"
require Rails.root.join("db/migrate/20261003120000_add_review_decision_to_release_notes")

RSpec.describe ReleaseNote, "review workflow gating" do
  let(:organization) { create(:organization, owner: create(:user, :team_plan)) }
  let(:app) { create(:apple_app, organization: organization) }

  context "in a solo organization" do
    it "never requires review, even for pending or rejected notes" do
      pending = create(:release_note, :pending_review, organization: organization, listable: app, version_string: "1.0.0")
      rejected = create(:release_note, :review_requested_changes, organization: organization, listable: app, version_string: "1.1.0")
      expect(pending).not_to be_review_required
      expect(rejected).not_to be_review_required
      expect(pending).to be_content_editable
    end

    it "lets a leftover pending_review note be edited and applied" do
      create(:store_listing, organization: organization, listable: app, locale: "en-US")
      note = create(:release_note, :pending_review, organization: organization, listable: app, version_string: "1.0.0")
      expect(note.update(rendered_text: "Solo edit")).to be(true)
      note.apply_to_store_listings!
      expect(note.reload.status).to eq("applied")
    end
  end

  context "in an organization with the review workflow" do
    before { organization.memberships.create!(user: create(:user), role: :developer) }

    it "requires review for pending and rejected notes but not approved ones" do
      pending = create(:release_note, :pending_review, organization: organization, listable: app, version_string: "1.0.0")
      rejected = create(:release_note, :review_requested_changes, organization: organization, listable: app, version_string: "1.1.0")
      approved = create(:release_note, organization: organization, listable: app, version_string: "1.2.0",
        submitted_for_review_at: 1.hour.ago, reviewed_at: 30.minutes.ago, review_decision: "approved", review_comment: "LGTM")
      expect(pending.reload).to be_review_required
      expect(rejected.reload).to be_review_required
      expect(approved.reload).not_to be_review_required
      expect(pending).not_to be_content_editable
    end
  end
end

RSpec.describe AddReviewDecisionToReleaseNotes do
  let(:connection) { ActiveRecord::Base.connection }
  let(:schema_name) { "review_decision_migration_spec_#{SecureRandom.hex(6)}" }

  around do |example|
    original_search_path = connection.schema_search_path
    connection.execute("CREATE SCHEMA #{schema_name}")
    connection.execute(<<~SQL)
      CREATE TABLE #{schema_name}.release_notes (
        id bigserial PRIMARY KEY,
        status character varying,
        reviewed_at timestamp,
        review_comment text
      )
    SQL
    connection.schema_search_path = "#{schema_name},public"
    example.run
  ensure
    connection.schema_search_path = original_search_path
    connection.execute("DROP SCHEMA IF EXISTS #{schema_name} CASCADE")
  end

  it "backfills completed legacy reviews as approved, including approvals with a comment" do
    connection.execute(<<~SQL)
      INSERT INTO #{schema_name}.release_notes (id, status, reviewed_at, review_comment) VALUES
        (1, 'applied', NOW(), 'Looks good, shipped'),
        (2, 'draft', NOW(), NULL),
        (3, 'pending_review', NULL, NULL)
    SQL

    described_class.new.migrate(:up)

    decisions = connection.select_rows("SELECT id, review_decision FROM #{schema_name}.release_notes ORDER BY id").to_h
    expect(decisions).to eq(1 => "approved", 2 => "approved", 3 => nil)
  end
end
