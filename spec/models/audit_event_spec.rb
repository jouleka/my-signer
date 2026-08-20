require "rails_helper"

RSpec.describe AuditEvent do
  let(:owner) { User.create!(email: "owner@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team) }
  let(:organization) { Organization.create!(name: "Audit Org", owner: owner) }

  describe "ACTIONS" do
    it "includes the 4 Phase 3 keyword-tracker actions" do
      %w[tracked_keyword_added tracked_keyword_removed apple_ads_credential_added apple_ads_credential_removed].each do |action|
        expect(described_class::ACTIONS).to include(action)
      end
    end
  end

  describe "new suggestions-tab actions" do
    it "includes store_listing_keywords_updated" do
      expect(AuditEvent::ACTIONS).to include("store_listing_keywords_updated")
    end

    it "includes keyword_idea_saved" do
      expect(AuditEvent::ACTIONS).to include("keyword_idea_saved")
    end

    it "includes keyword_idea_removed" do
      expect(AuditEvent::ACTIONS).to include("keyword_idea_removed")
    end
  end

  describe "ACTIONS constant" do
    it "includes the Phase 0 credential-read actions" do
      expect(described_class::ACTIONS).to include(
        "credential_read_android_keystore_file",
        "credential_read_android_keystore_secrets",
        "credential_read_google_play_token",
        "asc_build_upload_created",
        "asc_build_upload_finalized",
        "asc_build_upload_status_checked"
      )
    end
  end

  describe "Audit::Logger integration" do
    let(:org) { create(:organization) }
    let(:user) { create(:user) }

    it "persists a tracked_keyword_added event" do
      expect {
        Audit::Logger.log(
          action: :tracked_keyword_added,
          actor: user, organization: org,
          metadata: { keyword: "photo editor", countries: [ "us" ] }
        )
      }.to change { AuditEvent.count }.by(1)

      ae = AuditEvent.last
      expect(ae.action).to eq("tracked_keyword_added")
      expect(ae.organization_id).to eq(org.id)
      expect(ae.actor_id).to eq(user.id)
      expect(ae.metadata["keyword"]).to eq("photo editor")
    end

    it "persists an apple_ads_credential_added event" do
      expect {
        Audit::Logger.log(
          action: :apple_ads_credential_added,
          actor: user, organization: org,
          metadata: {}
        )
      }.to change { AuditEvent.count }.by(1)
    end
  end

  describe "validations" do
    it "requires a known action from the ACTIONS constant" do
      event = described_class.new(organization: organization, action: "not_a_real_action", created_at: Time.current)
      expect(event).not_to be_valid
      expect(event.errors[:action]).to include("is not included in the list")
    end

    it "accepts a valid action" do
      event = described_class.new(organization: organization, action: "member_invited", created_at: Time.current)
      expect(event).to be_valid
    end
  end

  describe "immutability" do
    let(:event) do
      described_class.create!(
        organization: organization,
        action: "member_invited",
        metadata: { email: "x@y.com" },
        created_at: Time.current
      )
    end

    it "raises ReadOnlyRecord when attempting to update" do
      expect { event.update!(action: "member_removed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ReadOnlyRecord when attempting to destroy" do
      expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe ".delete_before" do
    it "bulk-deletes records older than the cutoff without triggering destroy callbacks" do
      old_event = described_class.create!(
        organization: organization,
        action: "member_invited",
        created_at: 2.years.ago
      )
      fresh_event = described_class.create!(
        organization: organization,
        action: "member_invited",
        created_at: 1.day.ago
      )

      expect {
        described_class.delete_before(1.year.ago)
      }.to change(described_class, :count).by(-1)

      expect(described_class.exists?(old_event.id)).to be false
      expect(described_class.exists?(fresh_event.id)).to be true
    end
  end

  describe "scopes" do
    before do
      described_class.create!(organization: organization, actor: owner, action: "member_invited", created_at: 2.days.ago)
      described_class.create!(organization: organization, actor: owner, action: "member_removed", created_at: 1.day.ago)
    end

    it ".recent orders newest first" do
      actions = organization.audit_events.recent.pluck(:action)
      expect(actions).to eq([ "member_removed", "member_invited" ])
    end

    it ".for_action filters by action" do
      expect(organization.audit_events.for_action("member_invited").count).to eq(1)
    end

    it ".for_actor filters by actor" do
      expect(organization.audit_events.for_actor(owner.id).count).to eq(2)
    end
  end

  describe "#actor_display" do
    it "returns 'System' when actor is nil" do
      event = described_class.new(action: "member_invited", organization: organization, actor: nil)
      expect(event.actor_display).to eq("System")
    end

    it "returns the actor's name when present" do
      owner.update!(name: "Owner Name")
      event = described_class.new(action: "member_invited", organization: organization, actor: owner)
      expect(event.actor_display).to eq("Owner Name")
    end

    it "falls back to email when name is blank" do
      event = described_class.new(action: "member_invited", organization: organization, actor: owner)
      expect(event.actor_display).to eq(owner.email)
    end
  end
end
