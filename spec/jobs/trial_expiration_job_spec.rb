require "rails_helper"

RSpec.describe TrialExpirationJob do
  include ActiveJob::TestHelper

  describe "#perform" do
    it "downgrades users whose trial has expired and are on pro" do
      user = create_user_with_trial(email: "expired@example.com", trial_ends_at: 1.day.ago)

      expect { described_class.new.perform }.to change { user.reload.plan_tier }.from("pro").to("free")
    end

    it "does not downgrade users whose trial is still active" do
      user = create_user_with_trial(email: "active@example.com", trial_ends_at: 7.days.from_now)

      described_class.new.perform

      expect(user.reload.plan_tier).to eq("pro")
    end

    it "does not downgrade users who have an active billing subscription" do
      user = create_user_with_trial(email: "upgraded@example.com", trial_ends_at: 1.day.ago)
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_active_123",
        provider_customer_id: "ctm_active_123",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )

      described_class.new.perform

      expect(user.reload.plan_tier).to eq("pro")
    end

    it "ignores users without a trial_ends_at (grandfathered)" do
      user = User.create!(
        email: "grandfathered@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :free
      )

      described_class.new.perform

      expect(user.reload.plan_tier).to eq("free")
      expect(user.trial_ends_at).to be_nil
    end

    it "ignores users on team plan (admin-provisioned, not trial)" do
      user = User.create!(
        email: "team-admin@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :team
      )

      described_class.new.perform

      expect(user.reload.plan_tier).to eq("team")
    end

    it "downgrades multiple expired users in a single run" do
      user_a = create_user_with_trial(email: "alpha@example.com", trial_ends_at: 2.days.ago)
      user_b = create_user_with_trial(email: "beta@example.com", trial_ends_at: 1.day.ago)
      unaffected = create_user_with_trial(email: "charlie@example.com", trial_ends_at: 5.days.from_now)

      described_class.new.perform

      expect(user_a.reload.plan_tier).to eq("free")
      expect(user_b.reload.plan_tier).to eq("free")
      expect(unaffected.reload.plan_tier).to eq("pro")
    end

    # Pins the atomicity contract: when the downgrade happens, audit events
    # are written in the same transaction (one per owned organization). When
    # the downgrade is skipped (e.g., an active subscription exists), no
    # audit event is written. This prevents drift between plan state and
    # the audit log that used to exist when the audit write lived in a
    # separate loop after the transaction closed.
    describe "audit event atomicity" do
      it "writes a trial_expired audit event for each owned org when downgrading" do
        user = create_user_with_trial(email: "atomic@example.com", trial_ends_at: 1.day.ago)
        org_a = Organization.create!(name: "Atomic Org A", owner: user)
        org_b = Organization.create!(name: "Atomic Org B", owner: user)

        expect {
          described_class.new.perform
        }.to change { AuditEvent.where(action: "trial_expired").count }.by(2)

        actions = AuditEvent.where(action: "trial_expired").pluck(:organization_id)
        expect(actions).to contain_exactly(org_a.id, org_b.id)
      end

      it "does NOT write an audit event when the downgrade is skipped (active subscription)" do
        user = create_user_with_trial(email: "skipped@example.com", trial_ends_at: 1.day.ago)
        BillingSubscription.create!(
          user: user,
          provider: "paddle",
          provider_subscription_id: "sub_skipped_123",
          provider_customer_id: "ctm_skipped_123",
          provider_plan_id: "pri_pro_monthly",
          status: "active",
          plan_tier: "pro",
          billing_interval: "monthly"
        )
        Organization.create!(name: "Skipped Org", owner: user)

        expect {
          described_class.new.perform
        }.not_to change { AuditEvent.where(action: "trial_expired").count }
      end
    end
  end

  context "notifications on downgrade" do
    let!(:user) do
      u = User.create!(email: "expiring@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
      u.update_columns(
        plan_tier: User.plan_tiers[:pro],
        trial_started_at: 15.days.ago,
        trial_ends_at: 1.day.ago,
        notify_billing_changes: true
      )
      u
    end
    let!(:organization) { create(:organization, owner: user) }

    it "sends the expired email and creates an in-app notification" do
      expect {
        perform_enqueued_jobs { described_class.perform_now }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)
       .and change(Notification, :count).by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ user.email ])
      expect(mail.subject).to include("trial has ended")

      notification = Notification.last
      expect(notification.user).to eq(user)
      expect(notification.notification_type).to eq("trial_expired")
    end

    it "skips email when user has notify_billing_changes disabled" do
      user.update!(notify_billing_changes: false)

      expect {
        perform_enqueued_jobs { described_class.perform_now }
      }.not_to change(ActionMailer::Base.deliveries, :count)
    end
  end

  # Creates a user that simulates a trial state (pro plan + trial_ends_at set).
  # Bypasses the normal after_create trial callback to allow precise control
  # over trial_ends_at in test scenarios.
  def create_user_with_trial(email:, trial_ends_at:)
    user = User.create!(
      email: email,
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :free
    )
    user.update_columns(
      plan_tier: User.plan_tiers[:pro],
      trial_started_at: trial_ends_at - 14.days,
      trial_ends_at: trial_ends_at
    )
    user
  end
end
