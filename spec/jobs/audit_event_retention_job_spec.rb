require "rails_helper"

RSpec.describe AuditEventRetentionJob do
  let(:owner) do
    User.create!(
      email: "retention-owner@example.com",
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :team
    )
  end
  let(:organization) { Organization.create!(name: "Retention Org", owner: owner) }

  # Reference the retention constant rather than hardcoding 365 so the spec
  # tracks the production contract if the window ever changes.
  let(:window_days) { AuditEventRetentionJob::RETENTION_DAYS }

  describe "#perform" do
    it "deletes audit events older than the retention window" do
      old_event = AuditEvent.create!(
        organization: organization,
        action: "member_invited",
        metadata: {},
        created_at: (window_days + 5).days.ago
      )

      described_class.new.perform

      expect(AuditEvent.exists?(old_event.id)).to be(false)
    end

    it "preserves audit events inside the retention window" do
      fresh_event = AuditEvent.create!(
        organization: organization,
        action: "member_invited",
        metadata: {},
        created_at: (window_days - 5).days.ago
      )
      edge_event = AuditEvent.create!(
        organization: organization,
        action: "member_invited",
        metadata: {},
        created_at: 1.hour.ago
      )

      described_class.new.perform

      expect(AuditEvent.exists?(fresh_event.id)).to be(true)
      expect(AuditEvent.exists?(edge_event.id)).to be(true)
    end

    it "bypasses the AuditEvent before_destroy immutability guard" do
      # The production intent: delete_all issues a raw DELETE that bypasses
      # the `before_destroy { raise ReadOnlyRecord }` guard on AuditEvent.
      # If a future refactor swapped to .destroy_all or any path that loads
      # records, the guard would fire and this spec would raise.
      AuditEvent.create!(
        organization: organization,
        action: "member_invited",
        metadata: {},
        created_at: (window_days + 30).days.ago
      )

      expect {
        described_class.new.perform
      }.not_to raise_error
    end

    it "is idempotent: a second run does not delete additional rows or raise" do
      AuditEvent.create!(
        organization: organization,
        action: "member_invited",
        metadata: {},
        created_at: (window_days + 10).days.ago
      )
      fresh_event = AuditEvent.create!(
        organization: organization,
        action: "member_invited",
        metadata: {},
        created_at: 1.day.ago
      )

      described_class.new.perform
      remaining_after_first = AuditEvent.count

      expect {
        described_class.new.perform
      }.not_to raise_error

      expect(AuditEvent.count).to eq(remaining_after_first)
      expect(AuditEvent.exists?(fresh_event.id)).to be(true)
    end

    it "deletes nothing when no events are past the retention window" do
      AuditEvent.create!(
        organization: organization,
        action: "member_invited",
        metadata: {},
        created_at: 1.day.ago
      )

      expect {
        described_class.new.perform
      }.not_to change(AuditEvent, :count)
    end
  end
end
