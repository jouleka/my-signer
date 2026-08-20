require "rails_helper"

RSpec.describe TeamMemberJoinedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin_user) { create(:user, :team_plan, notify_team_activity: true) }
  let(:organization) { create(:organization, owner: admin_user) }
  let(:new_member) { create(:user, name: "Jane Doe") }

  before do
    organization.memberships.find_or_create_by!(user: admin_user) { |m| m.role = :admin }
    create(:membership, user: new_member, organization: organization, role: :developer)
  end

  describe "#perform" do
    it "creates notifications for existing members but not the new member" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          new_member_id: new_member.id
        )
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification.user).to eq(admin_user)
      expect(notification.notification_type).to eq("team_member_joined")
      expect(notification.title).to eq("New Team Member")
      expect(notification.message).to include("Jane Doe")
      expect(notification.message).to include(organization.name)
    end

    it "does not notify the new member themselves" do
      described_class.perform_now(
        organization_id: organization.id,
        new_member_id: new_member.id
      )

      expect(Notification.where(user: new_member)).to be_empty
    end

    it "sends email to admin members only" do
      viewer = create(:user, notify_team_activity: true)
      create(:membership, user: viewer, organization: organization, role: :viewer)

      expect {
        perform_enqueued_jobs {
          described_class.perform_now(
            organization_id: organization.id,
            new_member_id: new_member.id
          )
        }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to include(admin_user.email)
      expect(mail.to).not_to include(viewer.email)
    end

    it "creates in-app notifications for non-admin members too" do
      viewer = create(:user, notify_team_activity: true)
      create(:membership, user: viewer, organization: organization, role: :viewer)

      described_class.perform_now(
        organization_id: organization.id,
        new_member_id: new_member.id
      )

      expect(Notification.where(user: viewer, notification_type: "team_member_joined")).to exist
    end

    it "respects the notify_team_activity preference" do
      admin_user.update!(notify_team_activity: false)

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          new_member_id: new_member.id
        )
      }.not_to change(Notification, :count)
    end

    it "uses email when user has no name" do
      nameless_member = create(:user, name: nil)
      create(:membership, user: nameless_member, organization: organization, role: :developer)

      described_class.perform_now(
        organization_id: organization.id,
        new_member_id: nameless_member.id
      )

      notification = Notification.where(notification_type: "team_member_joined").last
      expect(notification.message).to include(nameless_member.email)
    end

    it "silently returns when organization is not found" do
      expect {
        described_class.perform_now(
          organization_id: -1,
          new_member_id: new_member.id
        )
      }.not_to change(Notification, :count)
    end

    it "silently returns when new member is not found" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          new_member_id: -1
        )
      }.not_to change(Notification, :count)
    end
  end
end
