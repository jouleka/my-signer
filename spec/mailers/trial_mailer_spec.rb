require "rails_helper"

RSpec.describe TrialMailer, type: :mailer do
  let(:user) do
    u = User.create!(email: "trial@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :free)
    u.update_columns(
      plan_tier: User.plan_tiers[:pro],
      trial_started_at: 7.days.ago,
      trial_ends_at: 7.days.from_now
    )
    u
  end

  describe "#halfway" do
    let(:mail) { described_class.halfway(user: user) }

    it "addresses the user and uses the halfway subject" do
      expect(mail.to).to eq([ user.email ])
      expect(mail.subject).to include("halfway")
      expect(mail.subject).to include("7 days")
    end

    it "renders the trial end date in the body" do
      expect(mail.body.encoded).to include(user.trial_ends_at.strftime("%B %d, %Y"))
    end

    it "includes an upgrade link to the pricing page" do
      expect(mail.body.encoded).to include("pricing")
    end
  end

  describe "#three_days_left" do
    let(:mail) { described_class.three_days_left(user: user) }

    it "uses the 3-day subject" do
      expect(mail.to).to eq([ user.email ])
      expect(mail.subject).to include("3 days left")
    end
  end

  describe "#last_day" do
    let(:mail) { described_class.last_day(user: user) }

    it "uses the last-day subject" do
      expect(mail.to).to eq([ user.email ])
      expect(mail.subject).to include("Last day")
    end

    it "includes loss-aversion copy about tomorrow reverting to Free" do
      expect(mail.body.encoded).to include("Tomorrow")
    end
  end

  describe "#expired" do
    let(:mail) { described_class.expired(user: user) }

    it "addresses the user" do
      expect(mail.to).to eq([ user.email ])
    end

    it "uses the downgrade subject" do
      expect(mail.subject).to include("trial has ended")
    end

    it "explains the downgrade to Free tier" do
      expect(mail.body.encoded).to match(/downgraded to Free|now on the Free plan/i)
    end

    it "links to the pricing page so the user can upgrade" do
      expect(mail.body.encoded).to include("pricing")
    end
  end
end
