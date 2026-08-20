require "rails_helper"

RSpec.describe ResourceRevokedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin_user) { create(:user, :team_plan, notify_revocations: true) }
  let(:organization) { create(:organization, owner: admin_user) }
  let!(:cert) { create(:apple_certificate, organization: organization, name: "Distribution Cert") }

  before do
    organization.memberships.find_or_create_by!(user: admin_user) { |m| m.role = :admin }
  end

  describe "#perform" do
    it "creates a notification for each org member" do
      member = create(:user, notify_revocations: true)
      create(:membership, user: member, organization: organization, role: :developer)

      expect {
        described_class.perform_now(
          resource_type: "AppleCertificate",
          resource_id: cert.id,
          organization_id: organization.id
        )
      }.to change(Notification, :count).by(2)

      notifications = Notification.where(notification_type: "resource_revoked")
      expect(notifications.pluck(:user_id)).to contain_exactly(admin_user.id, member.id)
    end

    it "sets correct notification attributes" do
      described_class.perform_now(
        resource_type: "AppleCertificate",
        resource_id: cert.id,
        organization_id: organization.id
      )

      notification = Notification.last
      expect(notification.notification_type).to eq("resource_revoked")
      expect(notification.title).to include("Revoked")
      expect(notification.message).to include("Distribution Cert")
      expect(notification.message).to include("revoked")
      expect(notification.resource_type).to eq("AppleCertificate")
      expect(notification.resource_id).to eq(cert.id)
    end

    it "sends an email for each member" do
      expect {
        perform_enqueued_jobs {
          described_class.perform_now(
            resource_type: "AppleCertificate",
            resource_id: cert.id,
            organization_id: organization.id
          )
        }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to include("revoked")
    end

    it "respects the notify_revocations preference" do
      admin_user.update!(notify_revocations: false)

      expect {
        described_class.perform_now(
          resource_type: "AppleCertificate",
          resource_id: cert.id,
          organization_id: organization.id
        )
      }.not_to change(Notification, :count)
    end

    it "only sends one notification per resource per user ever" do
      described_class.perform_now(
        resource_type: "AppleCertificate",
        resource_id: cert.id,
        organization_id: organization.id
      )

      expect {
        described_class.perform_now(
          resource_type: "AppleCertificate",
          resource_id: cert.id,
          organization_id: organization.id
        )
      }.not_to change(Notification, :count)
    end

    it "silently returns when organization is not found" do
      expect {
        described_class.perform_now(
          resource_type: "AppleCertificate",
          resource_id: cert.id,
          organization_id: -1
        )
      }.not_to change(Notification, :count)
    end

    it "silently returns when resource is not found" do
      expect {
        described_class.perform_now(
          resource_type: "AppleCertificate",
          resource_id: -1,
          organization_id: organization.id
        )
      }.not_to change(Notification, :count)
    end
  end
end
