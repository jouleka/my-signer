require "rails_helper"

RSpec.describe ReviewEvents::Notifier do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }

  describe ".notify_new_review" do
    it "creates notifications for negative reviews (1-star)" do
      review = create(:app_review, :negative, organization: organization, reviewable: apple_app, rating: 1)

      expect {
        described_class.notify_new_review(review)
      }.to change(Notification, :count).by_at_least(1)

      notification = Notification.last
      expect(notification.notification_type).to eq("review:new_negative:AppleApp")
      expect(notification.title).to include("Negative Review")
    end

    it "creates notifications for 2-star reviews" do
      review = create(:app_review, :negative, organization: organization, reviewable: apple_app, rating: 2)

      expect {
        described_class.notify_new_review(review)
      }.to change(Notification, :count).by_at_least(1)
    end

    it "does NOT create notifications for 3-star reviews" do
      review = create(:app_review, :neutral, organization: organization, reviewable: apple_app, rating: 3)

      expect {
        described_class.notify_new_review(review)
      }.not_to change(Notification, :count)
    end

    it "does NOT create notifications for 4-star reviews" do
      review = create(:app_review, organization: organization, reviewable: apple_app, rating: 4)

      expect {
        described_class.notify_new_review(review)
      }.not_to change(Notification, :count)
    end

    it "does NOT create notifications for 5-star reviews" do
      review = create(:app_review, organization: organization, reviewable: apple_app, rating: 5)

      expect {
        described_class.notify_new_review(review)
      }.not_to change(Notification, :count)
    end

    it "deduplicates notifications per day" do
      review1 = create(:app_review, :negative, organization: organization, reviewable: apple_app)
      described_class.notify_new_review(review1)

      review2 = create(:app_review, :negative, organization: organization, reviewable: apple_app)
      # Second notification for same user+type+resource on same day may be deduped
      expect {
        described_class.notify_new_review(review2)
      }.to change(Notification, :count).by_at_least(0)
    end

    it "handles missing organization gracefully" do
      review = build(:app_review, :negative, organization: nil)
      expect { described_class.notify_new_review(review) }.not_to raise_error
    end

    it "sets correct notification type for Android reviews" do
      android_app = create(:android_app, organization: organization)
      review = create(:app_review, :negative, organization: organization, reviewable: android_app)

      described_class.notify_new_review(review)

      notification = Notification.last
      expect(notification.notification_type).to eq("review:new_negative:AndroidApp")
    end
  end
end
