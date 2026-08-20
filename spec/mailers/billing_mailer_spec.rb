require "rails_helper"

RSpec.describe BillingMailer, type: :mailer do
  let(:user) { create(:user, email: "billing@example.com") }

  describe "#plan_changed" do
    let(:mail) { described_class.plan_changed(user: user, from_tier: "pro", to_tier: "team") }

    it "addresses the user" do
      expect(mail.to).to eq([ user.email ])
    end

    it "uses a descriptive upgrade subject" do
      expect(mail.subject).to include("Team")
    end

    it "mentions the target plan in the body" do
      expect(mail.body.encoded).to match(/Team/i)
    end
  end

  describe "#payment_past_due" do
    let(:mail) { described_class.payment_past_due(user: user) }

    it "uses a past-due subject" do
      expect(mail.to).to eq([ user.email ])
      expect(mail.subject).to match(/payment|past due/i)
    end

    it "links to the billing portal" do
      expect(mail.body.encoded).to match(/billing|portal|manage/i)
    end
  end

  describe "#subscription_cancelled" do
    let(:mail) { described_class.subscription_cancelled(user: user) }

    it "uses a cancellation subject" do
      expect(mail.to).to eq([ user.email ])
      expect(mail.subject).to match(/cancelled|canceled/i)
    end
  end
end
