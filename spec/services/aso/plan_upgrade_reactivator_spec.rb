require "rails_helper"

RSpec.describe Aso::PlanUpgradeReactivator do
  describe ".call" do
    let(:user) { create(:user, :pro_plan) }
    let(:org) { create(:organization, owner: user) }
    let(:app) { create(:apple_app, organization: org) }

    def build_paused_tkcs(count, country: "us")
      count.times.map do |i|
        tk = create(:tracked_keyword, apple_app: app, keyword: "paused-#{country}-#{i}")
        create(
          :tracked_keyword_country,
          tracked_keyword: tk,
          country: country,
          enabled: false,
          created_at: Time.current - (count - i).hours
        )
      end
    end

    it "re-enables paused TKCs oldest-first up to the new tier limit (Pro=50)" do
      # 3 active + 5 paused; Pro has plenty of headroom so all 5 resume.
      active = 3.times.map do |i|
        tk = create(:tracked_keyword, apple_app: app, keyword: "active-#{i}")
        create(:tracked_keyword_country, tracked_keyword: tk, country: "us")
      end
      paused = build_paused_tkcs(5)

      described_class.call(organization: org)

      expect(paused.map { |t| t.reload.enabled }).to all(be true)
      expect(active.map { |t| t.reload.enabled }).to all(be true)
    end

    it "respects the new-tier capacity when there are more paused than the limit" do
      # Drop org to Free (limit 5). 0 active, 10 paused. Only the 5 oldest
      # paused should resume; the 5 newest remain paused.
      user.update_columns(plan_tier: User.plan_tiers[:free])
      org.reset_entitlements_memo!

      paused = build_paused_tkcs(10)

      described_class.call(organization: org)

      expect(paused[0..4].map { |t| t.reload.enabled }).to all(be true)
      expect(paused[5..9].map { |t| t.reload.enabled }).to all(be false)
    end

    it "is a no-op when the active count is already at the limit" do
      user.update_columns(plan_tier: User.plan_tiers[:free])
      org.reset_entitlements_memo!

      # 5 active fills Free limit; 1 paused. Nothing can resume.
      5.times do |i|
        tk = create(:tracked_keyword, apple_app: app, keyword: "active-#{i}")
        create(:tracked_keyword_country, tracked_keyword: tk, country: "us")
      end
      paused = build_paused_tkcs(1)

      described_class.call(organization: org)

      expect(paused.first.reload.enabled).to be false
    end

    it "does not disturb already-active TKCs" do
      active = 3.times.map do |i|
        tk = create(:tracked_keyword, apple_app: app, keyword: "a-#{i}")
        create(:tracked_keyword_country, tracked_keyword: tk, country: "us")
      end

      described_class.call(organization: org)

      expect(active.map { |t| t.reload.enabled }).to all(be true)
    end

    it "reactivates per-app independently" do
      # Distinct sku because AppleApp's `before_validation :squish_fields`
      # converts nil sku to "", colliding with the per-org uniqueness check.
      app_b = create(:apple_app, organization: org, sku: "app-b-sku")
      user.update_columns(plan_tier: User.plan_tiers[:free])
      org.reset_entitlements_memo!

      paused_a = build_paused_tkcs(10)
      paused_b = 10.times.map do |i|
        tk = create(:tracked_keyword, apple_app: app_b, keyword: "b-#{i}")
        create(
          :tracked_keyword_country,
          tracked_keyword: tk,
          country: "us",
          enabled: false,
          created_at: Time.current - (10 - i).hours
        )
      end

      described_class.call(organization: org)

      # Each app independently resumes up to 5.
      expect(paused_a.count { |t| t.reload.enabled }).to eq(5)
      expect(paused_b.count { |t| t.reload.enabled }).to eq(5)
    end

    it "ignores paused TKCs whose parent TrackedKeyword is disabled" do
      disabled_tk = create(:tracked_keyword, apple_app: app, keyword: "dead-kw", enabled: false)
      dead_paused = create(
        :tracked_keyword_country,
        tracked_keyword: disabled_tk,
        country: "us",
        enabled: false,
        created_at: Time.current - 100.hours
      )

      described_class.call(organization: org)

      expect(dead_paused.reload.enabled).to be false
    end
  end
end
