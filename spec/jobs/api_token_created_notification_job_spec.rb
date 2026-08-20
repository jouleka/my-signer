require "rails_helper"

RSpec.describe ApiTokenCreatedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin_user) { create(:user, :team_plan, notify_team_activity: true) }
  let(:organization) { create(:organization, owner: admin_user) }
  let(:creator) { create(:user, name: "Bob Creator", notify_team_activity: true) }

  before do
    organization.memberships.find_or_create_by!(user: admin_user) { |m| m.role = :admin }
    create(:membership, user: creator, organization: organization, role: :admin)
  end

  describe "#perform" do
    it "creates a notification for admin members except the creator" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          creator_id: creator.id,
          token_name: "CI Token"
        )
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification.user).to eq(admin_user)
      expect(notification.notification_type).to eq("api_token_created")
      expect(notification.title).to eq("New API Token")
      expect(notification.message).to include("Bob Creator")
      expect(notification.message).to include("CI Token")
      expect(notification.message).to include(organization.name)
    end

    it "does not notify the creator" do
      described_class.perform_now(
        organization_id: organization.id,
        creator_id: creator.id,
        token_name: "CI Token"
      )

      expect(Notification.where(user: creator)).to be_empty
    end

    it "does not notify non-admin members" do
      viewer = create(:user, notify_team_activity: true)
      create(:membership, user: viewer, organization: organization, role: :viewer)

      described_class.perform_now(
        organization_id: organization.id,
        creator_id: creator.id,
        token_name: "CI Token"
      )

      expect(Notification.where(user: viewer)).to be_empty
    end

    it "sends an email to notified admins" do
      expect {
        perform_enqueued_jobs {
          described_class.perform_now(
            organization_id: organization.id,
            creator_id: creator.id,
            token_name: "CI Token"
          )
        }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to include(admin_user.email)
      expect(mail.subject).to include("API Token")
    end

    it "respects the notify_team_activity preference" do
      admin_user.update!(notify_team_activity: false)

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          creator_id: creator.id,
          token_name: "CI Token"
        )
      }.not_to change(Notification, :count)
    end

    it "uses email when creator has no name" do
      creator.update!(name: nil)

      described_class.perform_now(
        organization_id: organization.id,
        creator_id: creator.id,
        token_name: "Deploy Key"
      )

      notification = Notification.last
      expect(notification.message).to include(creator.email)
    end

    it "silently returns when organization is not found" do
      expect {
        described_class.perform_now(
          organization_id: -1,
          creator_id: creator.id,
          token_name: "CI Token"
        )
      }.not_to change(Notification, :count)
    end

    it "silently returns when creator is not found" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          creator_id: -1,
          token_name: "CI Token"
        )
      }.not_to change(Notification, :count)
    end
  end
end
