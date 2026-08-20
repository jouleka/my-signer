require "rails_helper"

RSpec.describe MembershipChangedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :team_plan, notify_member_activity: true) }
  let(:organization) { create(:organization, owner: admin) }
  let(:actor) { create(:user, name: "Olivia Admin", notify_member_activity: true) }
  let(:target) { create(:user, email: "target@example.com", notify_member_activity: true) }

  before do
    organization.memberships.find_or_create_by!(user: admin) { |m| m.role = :admin }
    create(:membership, user: actor, organization: organization, role: :admin)
  end

  describe "role_changed" do
    it "notifies the target user and other admins" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          actor_id: actor.id,
          target_user_id: target.id,
          event: "role_changed",
          metadata: { old_role: "viewer", new_role: "developer" }
        )
      }.to change(Notification, :count).by_at_least(1)

      messages = Notification.pluck(:message)
      expect(messages.any? { |m| m.include?("developer") }).to be true
    end
  end

  describe "removed" do
    it "notifies remaining admins" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          actor_id: actor.id,
          target_user_id: target.id,
          event: "removed",
          metadata: { role: "viewer" }
        )
      }.to change(Notification, :count).by_at_least(1)

      expect(Notification.last.notification_type).to eq("member_removed")
    end
  end

  it "respects notify_member_activity preference" do
    admin.update!(notify_member_activity: false)

    expect {
      described_class.perform_now(
        organization_id: organization.id,
        actor_id: actor.id,
        target_user_id: target.id,
        event: "removed",
        metadata: { role: "viewer" }
      )
    }.to change(Notification, :count).by(0)
  end
end
