require "rails_helper"

RSpec.describe Notification, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:cert) { create(:apple_certificate, organization: organization) }

  def build_notification(attrs = {})
    Notification.new(
      user: user,
      organization: organization,
      notification_type: "expiry_warning",
      title: "Test",
      message: "Test message",
      resource: cert,
      **attrs
    )
  end

  describe "associations" do
    it "belongs to a user" do
      notification = build_notification
      notification.save!
      expect(notification.user).to eq(user)
    end

    it "optionally belongs to an organization" do
      notification = build_notification(organization: nil)
      notification.save!
      expect(notification.organization).to be_nil
    end

    it "optionally belongs to a polymorphic resource" do
      notification = build_notification(resource: nil)
      notification.save!
      expect(notification.resource).to be_nil
    end
  end

  describe "validations" do
    it "prevents duplicate notifications for the same user, resource, type, and date" do
      build_notification.save!

      duplicate = build_notification
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:notification_date]).to include("already sent for this resource today")
    end

    it "allows same notification on different dates" do
      build_notification(notification_date: Date.yesterday).save!

      today_notification = build_notification(notification_date: Date.current)
      expect(today_notification).to be_valid
    end

    it "allows different notification types for same resource on same date" do
      build_notification(notification_type: "expiry_warning").save!

      expired = build_notification(notification_type: "expired")
      expect(expired).to be_valid
    end

    it "allows same notification type for different resources on same date" do
      build_notification(resource: cert).save!

      other_cert = create(:apple_certificate, organization: organization, name: "Other Cert")
      other_notification = build_notification(resource: other_cert)
      expect(other_notification).to be_valid
    end

    it "skips uniqueness validation when resource_type is nil" do
      build_notification(resource: nil, notification_type: "team_member_joined").save!
      dup = build_notification(resource: nil, notification_type: "team_member_joined")
      expect(dup).to be_valid
    end
  end

  describe "callbacks" do
    it "sets notification_date to today on create" do
      notification = build_notification(notification_date: nil)
      notification.save!
      expect(notification.notification_date).to eq(Date.current)
    end

    it "does not override an explicitly set notification_date" do
      date = 5.days.ago.to_date
      notification = build_notification(notification_date: date)
      notification.save!
      expect(notification.notification_date).to eq(date)
    end
  end

  describe "scopes" do
    let!(:unread) { build_notification(notification_type: "expiry_warning", notification_date: 1.day.ago.to_date).tap(&:save!) }
    let!(:read_notif) { build_notification(notification_type: "expired", notification_date: 1.day.ago.to_date, read_at: 1.hour.ago).tap(&:save!) }
    let!(:dismissed) { build_notification(notification_type: "sync_failed", notification_date: 1.day.ago.to_date, resource: nil, dismissed_at: 1.hour.ago).tap(&:save!) }

    it ".unread returns notifications without read_at" do
      expect(Notification.unread).to include(unread, dismissed)
      expect(Notification.unread).not_to include(read_notif)
    end

    it ".read returns notifications with read_at" do
      expect(Notification.read).to include(read_notif)
      expect(Notification.read).not_to include(unread)
    end

    it ".visible returns notifications without dismissed_at" do
      expect(Notification.visible).to include(unread, read_notif)
      expect(Notification.visible).not_to include(dismissed)
    end

    it ".recent orders by created_at desc" do
      expect(Notification.recent.first).to eq(Notification.order(created_at: :desc).first)
    end
  end

  describe "instance methods" do
    let(:notification) { build_notification.tap(&:save!) }

    describe "#read?" do
      it "returns false when read_at is nil" do
        expect(notification.read?).to be false
      end

      it "returns true when read_at is set" do
        notification.mark_as_read!
        expect(notification.read?).to be true
      end
    end

    describe "#mark_as_read!" do
      it "sets read_at to current time" do
        expect { notification.mark_as_read! }.to change(notification, :read_at).from(nil)
        expect(notification.read_at).to be_within(1.second).of(Time.current)
      end
    end

    describe "#dismissed?" do
      it "returns false when dismissed_at is nil" do
        expect(notification.dismissed?).to be false
      end

      it "returns true when dismissed_at is set" do
        notification.dismiss!
        expect(notification.dismissed?).to be true
      end
    end

    describe "#dismiss!" do
      it "sets dismissed_at to current time" do
        expect { notification.dismiss! }.to change(notification, :dismissed_at).from(nil)
        expect(notification.dismissed_at).to be_within(1.second).of(Time.current)
      end
    end
  end
end
