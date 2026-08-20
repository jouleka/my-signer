require "rails_helper"

RSpec.describe Audit::Logger do
  let(:owner) { User.create!(email: "actor@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team) }
  let(:organization) { Organization.create!(name: "Logger Org", owner: owner) }

  describe ".log" do
    it "creates an AuditEvent with action, actor, organization, and metadata" do
      expect {
        described_class.log(
          action: "member_invited",
          actor: owner,
          organization: organization,
          metadata: { email: "new@example.com", role: "developer" }
        )
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(event.action).to eq("member_invited")
      expect(event.actor).to eq(owner)
      expect(event.organization).to eq(organization)
      expect(event.metadata).to eq({ "email" => "new@example.com", "role" => "developer" })
    end

    it "silently skips when action is not in the canonical list (and warns)" do
      expect(Rails.logger).to receive(:warn).with(/unknown action.*bogus_action/i)

      expect {
        described_class.log(action: "bogus_action", organization: organization)
      }.not_to change(AuditEvent, :count)
    end

    it "silently skips when organization is missing (and warns)" do
      expect(Rails.logger).to receive(:warn).with(/organization is nil/)

      expect {
        described_class.log(action: "member_invited", organization: nil)
      }.not_to change(AuditEvent, :count)
    end

    it "swallows exceptions and returns nil on write failure" do
      allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect(Rails.logger).to receive(:error).with(/member_invited/)

      result = described_class.log(action: "member_invited", organization: organization, actor: owner)

      expect(result).to be_nil
    end

    it "falls back to Current.user and Current.organization when not provided" do
      Current.user = owner
      Current.organization = organization

      expect {
        described_class.log(action: "member_invited")
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(event.actor).to eq(owner)
      expect(event.organization).to eq(organization)
    ensure
      Current.reset
    end

    it "truncates IPv4 addresses to /24 for privacy" do
      request = instance_double(
        ActionDispatch::Request,
        remote_ip: "203.0.113.42",
        user_agent: "Mozilla/5.0"
      )

      described_class.log(
        action: "member_invited",
        organization: organization,
        actor: owner,
        request: request
      )

      expect(AuditEvent.last.ip_address).to eq("203.0.113.x")
    end

    it "records the resource polymorphically" do
      invitation = organization.organization_invitations.create!(
        inviter: owner,
        email: "invitee@example.com",
        role: :developer
      )

      described_class.log(
        action: "member_invited",
        organization: organization,
        actor: owner,
        resource: invitation
      )

      event = AuditEvent.last
      expect(event.resource_type).to eq("OrganizationInvitation")
      expect(event.resource_id).to eq(invitation.id)
      expect(event.resource).to eq(invitation)
    end
  end
end
