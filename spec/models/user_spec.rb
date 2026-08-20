require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "is valid with a valid email and strong password" do
      user = described_class.new(email: "test@example.com", password: "SecurePassword123!")
      expect(user).to be_valid
    end

    it "requires an email" do
      user = described_class.new(email: "", password: "SecurePassword123!")
      expect(user).not_to be_valid
    end

    it "requires a password" do
      user = described_class.new(email: "test@example.com", password: "")
      expect(user).not_to be_valid
    end
  end

  describe "terms-of-service acceptance" do
    # Local override of the rails_helper-wide skip so this describe block
    # exercises the actual validation. The config-level `before(:each)` fires
    # first; this describe-level `before` runs after it and flips the switch
    # back to the real validation.
    before { User.skip_terms_acceptance_validation = false }

    it "rejects a sign-up that does not accept the terms" do
      user = described_class.new(email: "no-terms@example.com", password: "SecurePassword123!")
      expect(user).not_to be_valid
      expect(user.errors[:accepts_terms].join).to include("must be accepted")
    end

    it "accepts a sign-up that ticks the consent box and stamps the timestamp" do
      before_save = Time.current
      user = described_class.new(email: "with-terms@example.com", password: "SecurePassword123!", accepts_terms: "1")
      expect(user).to be_valid
      user.save!
      expect(user.terms_accepted_at).to be >= before_save
      expect(user.terms_accepted_at).to be <= Time.current
    end

    it "skips validation for OmniAuth sign-ups (provider present)" do
      user = described_class.new(
        email: "omniauth@example.com",
        password: "SecurePassword123!",
        provider: "google_oauth2",
        uid: "abc-123",
        terms_accepted_at: Time.current
      )
      expect(user).to be_valid
    end

    it "preserves an explicit terms_accepted_at without overwriting it" do
      explicit_time = 2.days.ago
      user = described_class.new(
        email: "preserved@example.com",
        password: "SecurePassword123!",
        terms_accepted_at: explicit_time,
        accepts_terms: "1"
      )
      expect(user).to be_valid
      user.save!
      expect(user.terms_accepted_at).to be_within(1.second).of(explicit_time)
    end
  end

  describe "password complexity" do
    it "rejects passwords without uppercase" do
      user = described_class.new(email: "test@example.com", password: "securepassword1!")
      expect(user).not_to be_valid
      expect(user.errors[:password].join).to include("uppercase")
    end

    it "rejects passwords without lowercase" do
      user = described_class.new(email: "test@example.com", password: "SECUREPASSWORD1!")
      expect(user).not_to be_valid
      expect(user.errors[:password].join).to include("lowercase")
    end

    it "rejects passwords without a digit" do
      user = described_class.new(email: "test@example.com", password: "SecurePassword!")
      expect(user).not_to be_valid
      expect(user.errors[:password].join).to include("digit")
    end

    it "rejects passwords without a symbol" do
      user = described_class.new(email: "test@example.com", password: "SecurePassword1")
      expect(user).not_to be_valid
      expect(user.errors[:password].join).to include("symbol")
    end

    it "rejects passwords containing the email username" do
      user = described_class.new(email: "johndoe@example.com", password: "Johndoe123!")
      expect(user).not_to be_valid
      expect(user.errors[:password].join).to include("email")
    end
  end

  describe "associations" do
    let(:user) { described_class.create!(email: "assoc@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }

    it "has many owned_organizations" do
      org = Organization.create!(name: "Owned Org", owner: user)
      expect(user.owned_organizations).to include(org)
    end

    it "destroys owned organizations when user is destroyed" do
      Organization.create!(name: "Owned Org", owner: user)
      expect { user.destroy }.to change(Organization, :count).by(-1)
    end
  end

  describe "plan tiers" do
    it "defaults new users to the free plan when plan_tier is omitted" do
      user = described_class.create!(
        email: "default-plan@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current
      )

      expect(user.plan_tier).to eq("free")
    end

    it "applies the free default at the database level for inserts without plan_tier" do
      email = "sql-default-#{SecureRandom.hex(4)}@example.com"
      now = Time.current

      sql = described_class.send(
        :sanitize_sql_array,
        [
          "INSERT INTO users (email, encrypted_password, confirmed_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
          email,
          "raw-password-digest",
          now,
          now,
          now
        ]
      )
      described_class.connection.execute(sql)

      expect(described_class.find_by!(email: email).plan_tier).to eq("free")
    end
  end

  describe "notification methods" do
    it "returns false for all notification types when notifications are disabled" do
      user = described_class.new(
        email: "notify@example.com", password: "SecurePassword123!",
        email_notifications_enabled: false,
        notify_certificate_expiry: true,
        notify_profile_expiry: true
      )

      expect(user.notifications_enabled?).to be false
      expect(user.notify_certificate_expiry?).to be false
      expect(user.notify_profile_expiry?).to be false
    end

    it "respects individual notification settings when notifications are enabled" do
      user = described_class.new(
        email: "notify@example.com", password: "SecurePassword123!",
        email_notifications_enabled: true,
        notify_certificate_expiry: true,
        notify_profile_expiry: false
      )

      expect(user.notifications_enabled?).to be true
      expect(user.notify_certificate_expiry?).to be true
      expect(user.notify_profile_expiry?).to be false
    end
  end

  describe "plan enforcement" do
    it "applies organization access limits when the plan tier changes" do
      user = described_class.create!(
        email: "plan-enforce@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :team
      )
      organizations = Array.new(4) { |index| Organization.create!(name: "Org #{index + 1}", owner: user) }

      user.update!(plan_tier: :free)

      expect(organizations.first.reload.access_state).to eq("active")
      expect(organizations.drop(1).map { |organization| organization.reload.access_state }).to all(eq("plan_blocked"))
    end
  end

  describe "keyword tracking plan change hook" do
    # Integration: the User after_commit callback is the single hook that fans
    # out to Aso::PlanDowngradePruner / Aso::PlanUpgradeReactivator on every
    # plan_tier mutation. It must fire for Paddle-webhook paths, the trial
    # expiration job, and any admin tooling alike -- all of which `update!`
    # plan_tier on User.
    let(:user) { create(:user, :pro_plan) }
    let(:org) { create(:organization, owner: user) }
    let(:app) { create(:apple_app, organization: org) }

    it "invokes PlanDowngradePruner when plan_tier decreases" do
      expect(Aso::PlanDowngradePruner).to receive(:call).with(organization: org)

      user.update!(plan_tier: :free)
    end

    it "invokes PlanUpgradeReactivator when plan_tier increases" do
      user.update!(plan_tier: :free)
      expect(Aso::PlanUpgradeReactivator).to receive(:call).with(organization: org)

      user.update!(plan_tier: :pro)
    end

    it "actually pauses excess TKCs end-to-end on a Pro->Free downgrade" do
      # Pro allows 50; Free allows 5. Create 8 TKCs so only 5 stay active.
      tkcs = 8.times.map do |i|
        tk = create(:tracked_keyword, apple_app: app, keyword: "kw-#{i}")
        create(
          :tracked_keyword_country,
          tracked_keyword: tk,
          country: "us",
          created_at: Time.current - (8 - i).hours
        )
      end
      # Sanity: the app exists and the callback runs on the owner record.
      expect(app.reload).to be_present

      user.update!(plan_tier: :free)

      active_count = tkcs.count { |t| t.reload.enabled }
      expect(active_count).to eq(5)
    end

    it "is a no-op when the per-app keyword limit is unchanged" do
      # Pro -> Team both widen limits. Build an entitlement scenario where
      # old_max == new_max so the pruner/reactivator callbacks early-return.
      free_entitlements = Pricing::Entitlements.new("free")
      allow(Pricing::Entitlements).to receive(:new).and_return(free_entitlements)

      expect(Aso::PlanDowngradePruner).not_to receive(:call)
      expect(Aso::PlanUpgradeReactivator).not_to receive(:call)

      user.update!(plan_tier: :team)
    end
  end

  describe "plan_tier after_commit callback ordering" do
    # Regression guard for a load-bearing ordering constraint documented on
    # the User model. Pricing::PlanEnforcer#apply! (invoked by
    # `enforce_plan_limits!`) opens `user.with_lock`, which reloads the
    # record and clears dirty-tracking state. Any after_commit callback
    # that runs AFTER `enforce_plan_limits!` and consults
    # `saved_change_to_plan_tier` will see nil and silently no-op — the
    # keyword-tracking fan-out (PlanDowngradePruner / PlanUpgradeReactivator)
    # would never fire. This spec asserts the real execution order so
    # swapping the declarations in user.rb fails loudly.
    it "fires handle_plan_tier_change_for_keyword_tracking! BEFORE enforce_plan_limits! on a real plan change" do
      user = create(:user, :pro_plan)
      create(:organization, owner: user)
      call_order = []

      allow(user).to receive(:handle_plan_tier_change_for_keyword_tracking!).and_wrap_original do |orig, *a, **kw|
        call_order << :keyword_handler
        orig.call(*a, **kw)
      end
      allow(user).to receive(:enforce_plan_limits!).and_wrap_original do |orig, *a, **kw|
        call_order << :enforcer
        orig.call(*a, **kw)
      end

      user.update!(plan_tier: :free)

      expect(call_order).to eq([ :keyword_handler, :enforcer ])
    end
  end

  describe "#entitlements" do
    # Deliberately NOT memoized on User. The same User object can persist across
    # boundaries (Devise/Warden in tests, background jobs, admin tooling) where
    # `plan_tier` may be mutated via `update_columns` without firing callbacks;
    # a stale memo there silently reports the wrong plan limits. Allocation here
    # is cheap (no DB), so we accept the duplication. Organization#entitlements
    # is the memoization boundary.
    it "returns fresh entitlements after a callback-bypass plan_tier mutation" do
      user = described_class.create!(
        email: "entitlements-fresh@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current
      )

      expect(user.entitlements.tier).to eq("free")

      user.update_columns(plan_tier: described_class.plan_tiers.fetch("pro"))

      expect(user.entitlements.tier).to eq("pro")
    end
  end

  describe "granular notification preferences" do
    let(:user) { create(:user) }

    it "#notify_member_activity? defaults to true and respects master toggle" do
      expect(user.notify_member_activity?).to be true
      user.update!(email_notifications_enabled: false)
      expect(user.notify_member_activity?).to be false
    end

    it "#notify_api_token_activity? respects the specific column" do
      user.update!(notify_api_token_activity: false)
      expect(user.notify_api_token_activity?).to be false
    end

    it "#notify_sso_activity? respects the specific column" do
      user.update!(notify_sso_activity: false)
      expect(user.notify_sso_activity?).to be false
    end

    it "#notify_security_alerts? respects the specific column" do
      user.update!(notify_security_alerts: false)
      expect(user.notify_security_alerts?).to be false
    end

    it "#notify_billing_changes? respects the specific column" do
      user.update!(notify_billing_changes: false)
      expect(user.notify_billing_changes?).to be false
    end

    it "#notify_release_activity? respects the specific column" do
      user.update!(notify_release_activity: false)
      expect(user.notify_release_activity?).to be false
    end

    it "#notify_audit_digest? defaults to false" do
      expect(user.notify_audit_digest?).to be false
    end
  end

  describe "Devise modules" do
    # L-7: idle sessions on a credential vault must expire. The :timeoutable
    # module enforces config.timeout_in (set in config/initializers/devise.rb).
    it "includes :timeoutable so idle sessions expire" do
      expect(described_class.devise_modules).to include(:timeoutable)
      expect(Devise.timeout_in).to eq(2.hours)
    end

    # L-9: confirmation links must expire (config.confirm_within in devise.rb).
    it "expires confirmation tokens via confirm_within" do
      expect(Devise.confirm_within).to eq(3.days)
    end
  end
end
