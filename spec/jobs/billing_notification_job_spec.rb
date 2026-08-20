require "rails_helper"

RSpec.describe BillingNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, notify_billing_changes: true) }

  describe "#perform" do
    it "sends plan_changed email and creates in-app notification on plan change" do
      expect {
        perform_enqueued_jobs {
          described_class.perform_now(user_id: user.id, event: "plan_changed", metadata: { from: "pro", to: "team" })
        }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)
       .and change(Notification, :count).by(1)
    end

    it "sends past_due email on payment_past_due event" do
      expect {
        perform_enqueued_jobs {
          described_class.perform_now(user_id: user.id, event: "payment_past_due", metadata: {})
        }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)
    end

    it "sends cancelled email on subscription_cancelled event" do
      expect {
        perform_enqueued_jobs {
          described_class.perform_now(user_id: user.id, event: "subscription_cancelled", metadata: {})
        }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)
    end

    it "respects notify_billing_changes preference" do
      user.update!(notify_billing_changes: false)

      expect {
        perform_enqueued_jobs {
          described_class.perform_now(user_id: user.id, event: "payment_past_due", metadata: {})
        }
      }.not_to change(ActionMailer::Base.deliveries, :count)
    end

    it "silently returns when user not found" do
      expect {
        described_class.perform_now(user_id: -1, event: "payment_past_due", metadata: {})
      }.not_to raise_error
    end
  end
end
