require 'rails_helper'

RSpec.describe Organization, type: :model do
  let(:user) { User.create!(email: "orgtest@example.com", password: "SecurePass123!", confirmed_at: Time.current) }

  describe "#brand_configured?" do
    it "returns false when brand_settings is empty" do
      org = described_class.create!(name: "Test Org", owner: user)
      expect(org.brand_configured?).to be false
    end

    it "returns false when brand_settings has only blank values" do
      org = described_class.create!(name: "Test Org", owner: user, brand_settings: { "primary_color" => "", "heading_font" => "" })
      expect(org.brand_configured?).to be false
    end

    it "returns true when brand_settings has at least one present value" do
      org = described_class.create!(name: "Test Org", owner: user, brand_settings: { "primary_color" => "#FF0000" })
      expect(org.brand_configured?).to be true
    end

    it "returns true with fully configured brand settings" do
      org = described_class.create!(name: "Test Org", owner: user, brand_settings: {
        "primary_color" => "#6366F1",
        "secondary_color" => "#8B5CF6",
        "text_color" => "#FFFFFF",
        "background_color" => "#000000",
        "heading_font" => "Poppins",
        "body_font" => "Inter"
      })
      expect(org.brand_configured?).to be true
    end
  end

  describe "#byok_kms_key_arn validation" do
    # The regex MUST reject anything that isn't a full us-east-1 key ARN
    # with a lowercase UUID. The design doc's "Schema" section calls this
    # out as the customer-facing contract; if it loosens, downstream code
    # (verifier, encrypt path) gets ambiguity it can't recover from.
    let(:valid_arn) { "arn:aws:kms:us-east-1:123456789012:key/abcdef01-2345-6789-abcd-ef0123456789" }

    it "accepts a fully-formed us-east-1 key ARN with lowercase UUID" do
      org = described_class.create!(name: "BYOK Valid", owner: user, byok_kms_key_arn: valid_arn)
      expect(org).to be_persisted
      expect(org.byok_kms_key_arn).to eq(valid_arn)
    end

    it "allows nil (BYOK not configured)" do
      org = described_class.create!(name: "BYOK Nil", owner: user, byok_kms_key_arn: nil)
      expect(org).to be_persisted
    end

    it "allows blank string (treated equivalent to nil at the column level)" do
      org = described_class.create!(name: "BYOK Blank", owner: user, byok_kms_key_arn: "")
      expect(org).to be_persisted
    end

    it "rejects an alias ARN (aliases resolve at call time and could be repointed)" do
      org = described_class.new(name: "BYOK Alias", owner: user,
        byok_kms_key_arn: "arn:aws:kms:us-east-1:123456789012:alias/my-customer-cmk")
      expect(org).not_to be_valid
      expect(org.errors[:byok_kms_key_arn].first).to include("alias and bare key IDs are not accepted")
    end

    it "rejects a bare key ID (no account ownership in audit logs)" do
      org = described_class.new(name: "BYOK Bare", owner: user,
        byok_kms_key_arn: [ "abcdef01", "2345", "6789", "abcd", "ef0123456789" ].join("-"))
      expect(org).not_to be_valid
      expect(org.errors[:byok_kms_key_arn]).to be_present
    end

    it "rejects an ARN in the wrong region (us-east-1 only in v1)" do
      org = described_class.new(name: "BYOK Region", owner: user,
        byok_kms_key_arn: "arn:aws:kms:eu-west-1:123456789012:key/abcdef01-2345-6789-abcd-ef0123456789")
      expect(org).not_to be_valid
      expect(org.errors[:byok_kms_key_arn]).to be_present
    end

    it "rejects an ARN with uppercase hex (regex is case-sensitive lowercase)" do
      org = described_class.new(name: "BYOK Upper", owner: user,
        byok_kms_key_arn: "arn:aws:kms:us-east-1:123456789012:key/ABCDEF01-2345-6789-ABCD-EF0123456789")
      expect(org).not_to be_valid
      expect(org.errors[:byok_kms_key_arn]).to be_present
    end

    it "rejects garbage (no aws prefix at all)" do
      org = described_class.new(name: "BYOK Junk", owner: user, byok_kms_key_arn: "not-an-arn")
      expect(org).not_to be_valid
      expect(org.errors[:byok_kms_key_arn]).to be_present
    end
  end

  describe "BYOK re-wrap callback (mysigner-21 sub-ticket 2.3)" do
    let(:valid_arn) { "arn:aws:kms:us-east-1:123456789012:key/abcdef01-2345-6789-abcd-ef0123456789" }
    let(:other_arn) { "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012" }

    it "fires only when byok_kms_key_arn actually changes" do
      # WHY: KMS round-trips cost money and latency. Saves that update name
      # or brand_settings on a BYOK-configured org MUST NOT re-wrap every
      # credential. The `if: :byok_kms_key_arn_changed?` guard is what
      # makes that affordable.
      org = described_class.create!(name: "Callback Test", owner: user, byok_kms_key_arn: valid_arn)

      # Re-loading wipes any in-memory dirty tracking. A subsequent
      # unrelated save MUST NOT trigger OrgRewrap.
      org.reload
      expect(CredentialVault::OrgRewrap).not_to receive(:run)
      org.update!(name: "Renamed")
    end

    it "passes the new ARN (presence-collapsed) into OrgRewrap on register" do
      # WHY: register path. The new value is in byok_kms_key_arn during
      # before_save, and the callback resolves new_arn = byok_kms_key_arn.presence
      # before passing it on. If presence-collapsing broke, a customer
      # setting "" would land "" inside OrgRewrap and CredentialVault would
      # try to call KMS with key_id: "" — which AWS rejects with a much
      # less obvious error.
      org = described_class.create!(name: "Register Test", owner: user)

      expect(CredentialVault::OrgRewrap).to receive(:run)
        .with(organization: org, key_arn: valid_arn)
        .and_return({ AppStoreConnectCredential: { processed: 0, succeeded: 0 } })

      org.update!(byok_kms_key_arn: valid_arn)
    end

    it "passes nil into OrgRewrap on clear (symmetric to register)" do
      # WHY: clear path. The column moves from a populated ARN to nil; the
      # callback resolves new_arn = nil and OrgRewrap re-wraps under the
      # env default. If the callback accidentally read the OLD value, the
      # clear would never actually re-wrap anything off the customer CMK.
      org = described_class.create!(name: "Clear Test", owner: user, byok_kms_key_arn: valid_arn)

      expect(CredentialVault::OrgRewrap).to receive(:run)
        .with(organization: org, key_arn: nil)
        .and_return({ AppStoreConnectCredential: { processed: 0, succeeded: 0 } })

      org.update!(byok_kms_key_arn: nil)
    end

    it "exposes the OrgRewrap result via last_rewrap_counts after a successful save" do
      # WHY: the controller reads this attr_reader to surface counts in the
      # byok_registered/byok_cleared audit metadata. If it stops being
      # populated, the audit emission silently falls back to {} and the
      # forensics trail loses the per-class numbers.
      counts = {
        AppStoreConnectCredential: { processed: 3, succeeded: 3 },
        GooglePlayCredential:      { processed: 0, succeeded: 0 },
        AndroidKeystore:           { processed: 0, succeeded: 0 },
        AppleAdsCredential:        { processed: 0, succeeded: 0 }
      }
      org = described_class.create!(name: "Counts Test", owner: user)
      allow(CredentialVault::OrgRewrap).to receive(:run).and_return(counts)

      org.update!(byok_kms_key_arn: valid_arn)

      expect(org.last_rewrap_counts).to eq(counts)
    end

    it "aborts the save and adds a model error when OrgRewrap raises Aws::KMS::Errors::ServiceError" do
      # WHY: the design doc's atomicity contract — KMS failure means the
      # whole transaction rolls back, the byok_kms_key_arn column stays at
      # its previous value, and the customer sees an actionable error in
      # the controller flash. Without the throw :abort, the column would
      # update to a value we couldn't actually encrypt under, leaving the
      # org in an inconsistent state.
      org = described_class.create!(name: "KMS Fail Test", owner: user)
      allow(CredentialVault::OrgRewrap).to receive(:run).and_raise(
        Aws::KMS::Errors::ServiceError.new(nil, "simulated KMS failure")
      )

      result = org.update(byok_kms_key_arn: valid_arn)

      expect(result).to be false
      expect(org.errors[:byok_kms_key_arn]).to include(a_string_matching(/could not be applied/))
      # And the column actually rolled back — not just the validation error.
      expect(org.reload.byok_kms_key_arn).to be_nil
    end

    it "skips the callback entirely when byok_kms_key_arn isn't touched (most saves)" do
      # WHY: separate from the "changes attr on a BYOK org" guard — this
      # locks the case where the BYOK column is in the same NIL state
      # before and after the save. By far the most common case (any save
      # of a non-BYOK org), and it must never call KMS.
      org = described_class.create!(name: "Quiet Save", owner: user)
      expect(org.byok_kms_key_arn).to be_nil

      expect(CredentialVault::OrgRewrap).not_to receive(:run)
      org.update!(name: "Renamed Quiet")
    end

    it "fires when migrating from one ARN to a different ARN" do
      # WHY: the design doc's "Customer migrates to a different CMK"
      # subsection — internally treated as Clear + Register. The callback
      # MUST fire on any change (including arn_a → arn_b), not just on
      # nil-boundaries.
      org = described_class.create!(name: "Migrate Test", owner: user, byok_kms_key_arn: valid_arn)

      expect(CredentialVault::OrgRewrap).to receive(:run)
        .with(organization: org, key_arn: other_arn)
        .and_return({ AppStoreConnectCredential: { processed: 0, succeeded: 0 } })

      org.update!(byok_kms_key_arn: other_arn)
    end
  end

  describe "owner organization limit" do
    it "allows free users to create up to their plan limit" do
      limit = user.entitlements.max_owned_organizations

      limit.times do |i|
        described_class.create!(name: "Org #{i + 1}", owner: user)
      end

      expect(user.reload.owned_organizations.count).to eq(limit)
    end

    it "rejects creating beyond the free plan limit" do
      limit = user.entitlements.max_owned_organizations

      limit.times do |i|
        described_class.create!(name: "Org #{i + 1}", owner: user)
      end

      extra = described_class.new(name: "One Too Many", owner: user)
      expect(extra).not_to be_valid
      expect(extra.errors[:base]).to include("You can create a maximum of #{limit} organizations on the Free plan")
    end

    it "allows pro users to create up to three organizations" do
      user.update!(plan_tier: :pro)

      3.times do |i|
        described_class.create!(name: "Pro Org #{i + 1}", owner: user)
      end

      expect(user.reload.owned_organizations.count).to eq(3)
    end

    it "allows team users to create up to ten organizations" do
      user.update!(plan_tier: :team)

      10.times do |i|
        described_class.create!(name: "Team Org #{i + 1}", owner: user)
      end

      expect(user.reload.owned_organizations.count).to eq(10)
    end
  end

  describe ".enqueue_scheduled_sync_for" do
    let(:free_owner) { create(:user, email: "free-sync@example.com") }
    let(:pro_owner) { create(:user, :pro_plan, email: "pro-sync@example.com") }
    let(:team_owner) { create(:user, :team_plan, email: "team-sync@example.com") }
    let(:free_org) { create(:organization, owner: free_owner, name: "Free Sync") }
    let(:pro_org) { create(:organization, owner: pro_owner, name: "Pro Sync") }
    let(:team_org) { create(:organization, owner: team_owner, name: "Team Sync") }

    let(:asc_key_pem) { OpenSSL::PKey::EC.generate("prime256v1").to_pem }

    def create_asc(org, suffix)
      AppStoreConnectCredential.create!(
        organization: org,
        name: "ASC #{suffix}",
        key_id: "KEY#{suffix.to_s.upcase.ljust(7, 'X')}",
        issuer_id: "11111111-1111-1111-1111-1111#{suffix.to_s.rjust(8, '0')}",
        private_key: asc_key_pem,
        active: true
      )
    end

    def create_gp(org, suffix)
      GooglePlayCredential.create!(
        organization: org,
        name: "GP #{suffix}",
        service_account_json: {
          type: "service_account",
          project_id: "proj-#{suffix}",
          private_key: "-----BEGIN PRIVATE KEY-----\n#{suffix}\n-----END PRIVATE KEY-----\n",
          client_email: "svc-#{suffix}@example.com",
          client_id: "id-#{suffix}"
        }.to_json,
        active: true
      )
    end

    before do
      create_asc(free_org, "free")
      create_asc(pro_org, "pro")
      create_asc(team_org, "team")
      create_gp(free_org, "free")
      create_gp(pro_org, "pro")
      create_gp(team_org, "team")
    end

    it "enqueues App Store sync only for free-tier orgs when called with tier: 'free'" do
      expect {
        described_class.enqueue_scheduled_sync_for("app_store_connect", tier: "free")
      }.to have_enqueued_job(AppStoreConnectSyncJob).with(free_org.id).exactly(:once)

      expect(AppStoreConnectSyncJob).not_to have_been_enqueued.with(pro_org.id)
      expect(AppStoreConnectSyncJob).not_to have_been_enqueued.with(team_org.id)
    end

    it "enqueues App Store sync only for pro-tier orgs when called with tier: 'pro'" do
      expect {
        described_class.enqueue_scheduled_sync_for("app_store_connect", tier: "pro")
      }.to have_enqueued_job(AppStoreConnectSyncJob).with(pro_org.id).exactly(:once)

      expect(AppStoreConnectSyncJob).not_to have_been_enqueued.with(free_org.id)
      expect(AppStoreConnectSyncJob).not_to have_been_enqueued.with(team_org.id)
    end

    it "enqueues App Store sync only for team-tier orgs when called with tier: 'team'" do
      expect {
        described_class.enqueue_scheduled_sync_for("app_store_connect", tier: "team")
      }.to have_enqueued_job(AppStoreConnectSyncJob).with(team_org.id).exactly(:once)

      expect(AppStoreConnectSyncJob).not_to have_been_enqueued.with(free_org.id)
      expect(AppStoreConnectSyncJob).not_to have_been_enqueued.with(pro_org.id)
    end

    it "enqueues Google Play sync only for free-tier orgs when called with tier: 'free'" do
      expect {
        described_class.enqueue_scheduled_sync_for("google_play", tier: "free")
      }.to have_enqueued_job(GooglePlaySyncJob).with(free_org.id).exactly(:once)

      expect(GooglePlaySyncJob).not_to have_been_enqueued.with(pro_org.id)
      expect(GooglePlaySyncJob).not_to have_been_enqueued.with(team_org.id)
    end

    it "enqueues Google Play sync only for pro-tier orgs when called with tier: 'pro'" do
      expect {
        described_class.enqueue_scheduled_sync_for("google_play", tier: "pro")
      }.to have_enqueued_job(GooglePlaySyncJob).with(pro_org.id).exactly(:once)
    end

    it "enqueues Google Play sync only for team-tier orgs when called with tier: 'team'" do
      expect {
        described_class.enqueue_scheduled_sync_for("google_play", tier: "team")
      }.to have_enqueued_job(GooglePlaySyncJob).with(team_org.id).exactly(:once)
    end

    it "enqueues for every tier when called without a tier kwarg" do
      expect {
        described_class.enqueue_scheduled_sync_for("app_store_connect")
      }.to have_enqueued_job(AppStoreConnectSyncJob).with(free_org.id)
        .and have_enqueued_job(AppStoreConnectSyncJob).with(pro_org.id)
        .and have_enqueued_job(AppStoreConnectSyncJob).with(team_org.id)
    end

    it "raises on unknown tier" do
      expect {
        described_class.enqueue_scheduled_sync_for("app_store_connect", tier: "enterprise")
      }.to raise_error(KeyError)
    end

    it "applies tier-based jitter to fan-out so workers don't all start at the same instant" do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      now = Time.current
      travel_to now do
        described_class.enqueue_scheduled_sync_for("app_store_connect", tier: "free")
      end

      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == AppStoreConnectSyncJob }
      expect(jobs).not_to be_empty
      jobs.each do |job|
        expect(job[:at]).to be_present, "expected free-tier fan-out to schedule jobs with a future `at:` so they're spread within the jitter window"
        expect(job[:at]).to be <= (now + Organization::TIER_FAN_OUT_JITTER["free"]).to_f
        expect(job[:at]).to be >= now.to_f
      end
    end

    it "skips jitter when no tier is given (admin/manual fan-out fires immediately)" do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      described_class.enqueue_scheduled_sync_for("app_store_connect")

      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == AppStoreConnectSyncJob }
      expect(jobs).not_to be_empty
      jobs.each { |job| expect(job[:at]).to be_nil }
    end
  end

  describe ".enqueue_review_syncs" do
    let!(:free_org) { create(:organization, owner: create(:user, email: "rev-free@example.com")) }
    let!(:pro_org) { create(:organization, owner: create(:user, :pro_plan, email: "rev-pro@example.com")) }
    let!(:team_org) { create(:organization, owner: create(:user, :team_plan, email: "rev-team@example.com")) }

    it "filters to free orgs when called with tier: 'free'" do
      expect {
        described_class.enqueue_review_syncs(tier: "free")
      }.to have_enqueued_job(ReviewSyncJob).with(organization_id: free_org.id).exactly(:once)

      expect(ReviewSyncJob).not_to have_been_enqueued.with(organization_id: pro_org.id)
      expect(ReviewSyncJob).not_to have_been_enqueued.with(organization_id: team_org.id)
    end

    it "filters to pro orgs when called with tier: 'pro'" do
      expect {
        described_class.enqueue_review_syncs(tier: "pro")
      }.to have_enqueued_job(ReviewSyncJob).with(organization_id: pro_org.id).exactly(:once)
    end

    it "filters to team orgs when called with tier: 'team'" do
      expect {
        described_class.enqueue_review_syncs(tier: "team")
      }.to have_enqueued_job(ReviewSyncJob).with(organization_id: team_org.id).exactly(:once)
    end

    it "enqueues for every tier when called without a tier kwarg" do
      expect {
        described_class.enqueue_review_syncs
      }.to have_enqueued_job(ReviewSyncJob).with(organization_id: free_org.id)
        .and have_enqueued_job(ReviewSyncJob).with(organization_id: pro_org.id)
        .and have_enqueued_job(ReviewSyncJob).with(organization_id: team_org.id)
    end

    it "raises on unknown tier" do
      expect {
        described_class.enqueue_review_syncs(tier: "enterprise")
      }.to raise_error(KeyError)
    end
  end

  describe ".enqueue_analytics_syncs" do
    let!(:free_org) { create(:organization, owner: create(:user, email: "ana-free@example.com")) }
    let!(:pro_org) { create(:organization, owner: create(:user, :pro_plan, email: "ana-pro@example.com")) }
    let!(:team_org) { create(:organization, owner: create(:user, :team_plan, email: "ana-team@example.com")) }

    it "filters to free orgs when called with tier: 'free'" do
      expect {
        described_class.enqueue_analytics_syncs(tier: "free")
      }.to have_enqueued_job(AnalyticsSyncJob).with(organization_id: free_org.id).exactly(:once)

      expect(AnalyticsSyncJob).not_to have_been_enqueued.with(organization_id: pro_org.id)
      expect(AnalyticsSyncJob).not_to have_been_enqueued.with(organization_id: team_org.id)
    end

    it "filters to pro orgs when called with tier: 'pro'" do
      expect {
        described_class.enqueue_analytics_syncs(tier: "pro")
      }.to have_enqueued_job(AnalyticsSyncJob).with(organization_id: pro_org.id).exactly(:once)
    end

    it "filters to team orgs when called with tier: 'team'" do
      expect {
        described_class.enqueue_analytics_syncs(tier: "team")
      }.to have_enqueued_job(AnalyticsSyncJob).with(organization_id: team_org.id).exactly(:once)
    end

    it "raises on unknown tier" do
      expect {
        described_class.enqueue_analytics_syncs(tier: "enterprise")
      }.to raise_error(KeyError)
    end
  end

  describe "plan access helpers" do
    it "reports active organizations as accessible" do
      org = described_class.create!(name: "Active Org", owner: user)

      expect(org).to be_accessible
      expect(org).not_to be_blocked_by_plan
      expect(org.access_state_badge_text).to eq("Active")
    end

    it "reports blocked organizations with the plan badge text" do
      org = described_class.create!(name: "Blocked Org", owner: user, access_state: :plan_blocked)

      expect(org).not_to be_accessible
      expect(org).to be_blocked_by_plan
      expect(org.access_state_badge_text).to eq("Blocked by plan")
    end

    it "treats organizations as accessible during rollout before access_state exists" do
      org = described_class.create!(name: "Fallback Org", owner: user)
      allow(described_class).to receive(:access_state_supported?).and_return(false)

      expect(org).to be_accessible
      expect(org).not_to be_blocked_by_plan
      expect(org.access_state_badge_text).to eq("Active")
      expect(described_class.accessible).to include(org)
    end
  end

  # Audit events survive organization deletion so the compliance trail
  # (including the `organization_deleted` event itself) outlives the org.
  # The DB foreign key uses ON DELETE NULLIFY: destroying an organization
  # re-points `audit_events.organization_id` to NULL rather than cascading
  # the rows away. AuditEvent's `before_destroy` immutability guard is
  # irrelevant here because no Ruby-level destroy runs against the rows.
  # This spec catches a future refactor that switches to `dependent: :destroy`
  # or `dependent: :delete_all` (either would cut the trail silently).
  describe "audit events surviving org deletion" do
    let(:cascade_owner) do
      User.create!(
        email: "cascade-owner@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current,
        plan_tier: :team
      )
    end

    it "nullifies organization_id on associated audit events instead of deleting them" do
      org = described_class.create!(name: "Cascade Org", owner: cascade_owner)
      member = User.create!(
        email: "cascade-member@example.com",
        password: "SecurePassword123!",
        confirmed_at: Time.current
      )
      org.memberships.create!(user: member, role: :developer)

      event_ids = 3.times.map do |i|
        AuditEvent.create!(
          organization: org,
          actor: cascade_owner,
          action: "member_invited",
          metadata: { note: "event #{i}" },
          created_at: (i + 1).hours.ago
        ).id
      end

      expect(AuditEvent.where(id: event_ids).count).to eq(3)

      expect {
        org.destroy!
      }.not_to raise_error

      expect(described_class.exists?(org.id)).to be(false)
      # Rows survive; organization_id is now NULL courtesy of the FK.
      expect(AuditEvent.where(id: event_ids).count).to eq(3)
      expect(AuditEvent.where(id: event_ids).pluck(:organization_id).uniq).to eq([ nil ])
    end
  end

  describe "#entitlements" do
    it "memoizes the result while the owner's plan stays the same" do
      org = described_class.create!(name: "Memo Org", owner: user)

      first = org.entitlements
      second = org.entitlements

      # equal? checks object identity (not just value equality) — the same
      # entitlements object must be returned on every call within the request.
      expect(first).to be(second)
    end

    it "transparently refreshes when the owner's plan_tier changes" do
      org = described_class.create!(name: "Auto Refresh Org", owner: user)
      original = org.entitlements
      expect(original.tier).to eq("free")

      # Bypass callbacks the way an out-of-band system (background job, admin
      # console, paddle webhook applier) might.
      user.update_columns(plan_tier: User.plan_tiers.fetch("pro"))

      refreshed = org.entitlements
      expect(refreshed.tier).to eq("pro")
      expect(refreshed).not_to be(original)
    end
  end
end
