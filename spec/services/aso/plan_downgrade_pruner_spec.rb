require "rails_helper"

RSpec.describe Aso::PlanDowngradePruner do
  describe ".call" do
    let(:user) { create(:user, plan_tier: :free) }
    let(:org) { create(:organization, owner: user) }
    let(:app) { create(:apple_app, organization: org) }

    # Builds N tracked keyword-country pairs with staggered TKC created_at so
    # the oldest-first ordering is deterministic. The underlying TrackedKeyword
    # timestamps don't matter to the pruner -- it orders by TKC created_at.
    def build_tkcs(count, country: "us")
      count.times.map do |i|
        tk = create(:tracked_keyword, apple_app: app, keyword: "kw-#{country}-#{i}")
        create(
          :tracked_keyword_country,
          tracked_keyword: tk,
          country: country,
          created_at: Time.current - (count - i).hours,
          updated_at: Time.current - (count - i).hours
        )
      end
    end

    it "pauses excess TKCs oldest-first when downgrading to Free (limit 5)" do
      tkcs = build_tkcs(10)

      described_class.call(organization: org)

      # 5 oldest paused, 5 newest active.
      expect(tkcs[0..4].map { |t| t.reload.enabled }).to all(be false)
      expect(tkcs[5..9].map { |t| t.reload.enabled }).to all(be true)
    end

    it "is a no-op when active count is already within the new limit" do
      tk = create(:tracked_keyword, apple_app: app)
      tkc = create(:tracked_keyword_country, tracked_keyword: tk, country: "us")

      expect { described_class.call(organization: org) }
        .not_to change { tkc.reload.enabled }
    end

    it "does not re-enable already-paused TKCs" do
      tk = create(:tracked_keyword, apple_app: app)
      already_paused = create(
        :tracked_keyword_country,
        tracked_keyword: tk,
        country: "us",
        enabled: false
      )

      described_class.call(organization: org)

      expect(already_paused.reload.enabled).to be false
    end

    it "counts already-paused TKCs against the active pool, leaving them untouched" do
      # 5 newer active + 2 older already-paused. Free limit is 5. The 5 active
      # are within the limit, so no new pauses should fire. The 2 previously
      # paused remain paused.
      paused = 2.times.map do |i|
        tk = create(:tracked_keyword, apple_app: app, keyword: "old-paused-#{i}")
        create(
          :tracked_keyword_country,
          tracked_keyword: tk,
          country: "us",
          enabled: false,
          created_at: Time.current - (100 - i).hours
        )
      end
      active = build_tkcs(5)

      described_class.call(organization: org)

      expect(paused.map { |t| t.reload.enabled }).to all(be false)
      expect(active.map { |t| t.reload.enabled }).to all(be true)
    end

    it "prunes per-app independently (limit is per-app, not per-org)" do
      # Distinct sku because AppleApp's `before_validation :squish_fields`
      # converts `nil` sku to `""`, which trips the per-org uniqueness check
      # when two apps in the same org both default to nil.
      app_b = create(:apple_app, organization: org, sku: "app-b-sku")

      tkcs_a = build_tkcs(7)
      # Build 7 on app_b with a distinct country so app uniqueness constraints
      # don't collide, but keyword-per-app uniqueness isn't touched either.
      tkcs_b = 7.times.map do |i|
        tk = create(:tracked_keyword, apple_app: app_b, keyword: "b-#{i}")
        create(
          :tracked_keyword_country,
          tracked_keyword: tk,
          country: "us",
          created_at: Time.current - (7 - i).hours
        )
      end

      described_class.call(organization: org)

      # Each app prunes independently to 5 active.
      active_a = tkcs_a.count { |t| t.reload.enabled }
      active_b = tkcs_b.count { |t| t.reload.enabled }
      expect(active_a).to eq(5)
      expect(active_b).to eq(5)
    end

    it "ignores TKCs whose parent TrackedKeyword is disabled" do
      disabled_tk = create(:tracked_keyword, apple_app: app, keyword: "dead-kw", enabled: false)
      dead_tkc = create(
        :tracked_keyword_country,
        tracked_keyword: disabled_tk,
        country: "us",
        created_at: Time.current - 100.hours
      )

      # 5 fresh enabled TKCs -- below the Free limit even if the dead one is
      # counted. Pruner should not touch the dead row.
      active = build_tkcs(5)

      described_class.call(organization: org)

      expect(dead_tkc.reload.enabled).to be true
      expect(active.map { |t| t.reload.enabled }).to all(be true)
    end

    it "uses the organization's current tier for the limit" do
      # Team limit is 200; org owner is Free here. Switch owner to Team on the
      # fly and ensure we consult that tier.
      tkcs = build_tkcs(50)

      org.owner.update_columns(plan_tier: User.plan_tiers[:team])
      org.reset_entitlements_memo!

      described_class.call(organization: org)

      expect(tkcs.map { |t| t.reload.enabled }).to all(be true)
    end
  end
end
