require "rails_helper"

RSpec.describe NotificationCleanupJob, type: :job do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:cert) { create(:apple_certificate, organization: organization) }

  def create_notification(attrs = {})
    Notification.create!(
      user: user,
      organization: organization,
      notification_type: "expiry_warning",
      title: "Test",
      message: "Test message",
      resource: cert,
      notification_date: attrs[:notification_date] || Date.current,
      **attrs.except(:notification_date)
    )
  end

  describe "#perform" do
    it "deletes dismissed notifications older than 30 days" do
      old = create_notification(dismissed_at: 31.days.ago, notification_date: 31.days.ago.to_date)
      recent = create_notification(dismissed_at: 10.days.ago, notification_date: 10.days.ago.to_date)

      described_class.perform_now

      expect(Notification.exists?(old.id)).to be false
      expect(Notification.exists?(recent.id)).to be true
    end

    it "deletes read notifications older than 90 days" do
      old = create_notification(read_at: 91.days.ago, notification_date: 91.days.ago.to_date)
      recent = create_notification(read_at: 30.days.ago, notification_date: 30.days.ago.to_date)

      described_class.perform_now

      expect(Notification.exists?(old.id)).to be false
      expect(Notification.exists?(recent.id)).to be true
    end

    it "deletes unread notifications older than 365 days" do
      old = create_notification(created_at: 366.days.ago, notification_date: 366.days.ago.to_date)
      recent = create_notification(created_at: 100.days.ago, notification_date: 100.days.ago.to_date)

      described_class.perform_now

      expect(Notification.exists?(old.id)).to be false
      expect(Notification.exists?(recent.id)).to be true
    end

    it "does not delete read notifications that are not yet old enough" do
      notification = create_notification(read_at: 60.days.ago, notification_date: 60.days.ago.to_date)

      described_class.perform_now

      expect(Notification.exists?(notification.id)).to be true
    end
  end
end
