require "rails_helper"

RSpec.describe SyncFailedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :team_plan, notify_sync_failures: true) }
  let(:organization) { create(:organization, owner: user) }
  let(:credential_type) { "AppStoreConnectCredential" }
  let(:credential_id) { 999 }
  let(:error_message) { "Invalid API key" }

  # The owner membership is auto-created as admin
  before do
    # Ensure membership exists
    organization.memberships.find_or_create_by!(user: user) { |m| m.role = :admin }
  end

  describe "#perform" do
    it "creates a notification for admin members" do
      expect {
        described_class.perform_now(
          credential_type: credential_type,
          credential_id: credential_id,
          organization_id: organization.id,
          error_message: error_message
        )
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification.user).to eq(user)
      expect(notification.organization).to eq(organization)
      expect(notification.notification_type).to eq("sync_failed")
      expect(notification.title).to eq("Sync Failed")
      expect(notification.message).to include("sync failed")
      expect(notification.message).to include(error_message)
    end

    it "sends an email to admin members" do
      expect {
        perform_enqueued_jobs {
          described_class.perform_now(
            credential_type: credential_type,
            credential_id: credential_id,
            organization_id: organization.id,
            error_message: error_message
          )
        }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to include(user.email)
      expect(mail.subject).to include("Sync Failed")
    end

    it "does not notify non-admin members" do
      viewer = create(:user, notify_sync_failures: true)
      create(:membership, user: viewer, organization: organization, role: :viewer)

      described_class.perform_now(
        credential_type: credential_type,
        credential_id: credential_id,
        organization_id: organization.id,
        error_message: error_message
      )

      expect(Notification.where(user: viewer)).to be_empty
    end

    it "respects the notify_sync_failures preference" do
      user.update!(notify_sync_failures: false)

      expect {
        described_class.perform_now(
          credential_type: credential_type,
          credential_id: credential_id,
          organization_id: organization.id,
          error_message: error_message
        )
      }.not_to change(Notification, :count)
    end

    it "deduplicates within 24-hour window" do
      described_class.perform_now(
        credential_type: credential_type,
        credential_id: credential_id,
        organization_id: organization.id,
        error_message: error_message
      )

      expect {
        described_class.perform_now(
          credential_type: credential_type,
          credential_id: credential_id,
          organization_id: organization.id,
          error_message: "Different error"
        )
      }.not_to change(Notification, :count)
    end

    it "allows notification after dedup window expires" do
      described_class.perform_now(
        credential_type: credential_type,
        credential_id: credential_id,
        organization_id: organization.id,
        error_message: error_message
      )

      # Move the existing notification to 25 hours ago (both created_at and notification_date)
      Notification.last.update_columns(created_at: 25.hours.ago, notification_date: 1.day.ago.to_date)

      expect {
        described_class.perform_now(
          credential_type: credential_type,
          credential_id: credential_id,
          organization_id: organization.id,
          error_message: "New error"
        )
      }.to change(Notification, :count).by(1)
    end

    it "truncates long error messages" do
      long_error = "x" * 500
      described_class.perform_now(
        credential_type: credential_type,
        credential_id: credential_id,
        organization_id: organization.id,
        error_message: long_error
      )

      notification = Notification.last
      expect(notification.message.length).to be < 500
    end

    it "silently returns when organization is not found" do
      expect {
        described_class.perform_now(
          credential_type: credential_type,
          credential_id: credential_id,
          organization_id: -1,
          error_message: error_message
        )
      }.not_to change(Notification, :count)
    end
  end
end
