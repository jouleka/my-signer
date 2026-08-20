require "rails_helper"

# Consistency check between the user-facing role-permission matrix and the
# Pundit policies that actually enforce these capabilities. The matrix is
# rendered on the Permissions page (Team-tier feature) as ground truth for
# customers; if it drifts from the policies, we mislead users about what
# their roles can do.
#
# This spec walks every (row, role) pair in PermissionsHelper.permission_matrix
# and asserts that the matrix's claim equals the actual Pundit policy
# verdict for a real User+Membership of that role.
#
# Adding a new row to the matrix requires either a corresponding entry in
# pundit_verdict_for OR a documented entry in UNGATED_KEYS explaining why
# the row is intentionally not Pundit-enforced.
RSpec.describe PermissionsHelper, type: :helper do
  # Matrix rows that intentionally have no single corresponding Pundit method.
  # If a row is added to the matrix without a Pundit gate, document it here
  # with a justification rather than fabricating a policy method.
  UNGATED_KEYS = {}.freeze

  # Keys we know how to evaluate via Pundit. Used to validate the matrix
  # has full coverage. Any drift between this list and what
  # pundit_verdict_for actually handles will surface as a NotImplementedError.
  MAPPED_KEYS = %i[
    view_org_data
    sync_stores
    edit_store_listings
    push_to_stores
    ai_translate
    invite_members
    create_api_tokens
    manage_credentials
    manage_apple_ads_credential
    track_keywords
    remove_tracked_keywords
    change_member_roles
    invite_admins
    delete_store_listings
    view_audit_log
    delete_organization
  ].freeze

  # The audit-log row requires a Team-tier owner so AuditEventPolicy#team_tier?
  # passes. Other rows are agnostic to plan tier (org-level access_state alone
  # gates them via accessible?).
  let(:owner) do
    User.create!(
      email: "matrix-owner-#{SecureRandom.hex(4)}@example.com",
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :team
    )
  end
  let(:organization) { Organization.create!(name: "Matrix Org", owner: owner) }

  # Lazily build a StoreListing under the org for policies that authorize
  # against a child record (StoreListingPolicy). Memoized via let so the
  # multiple matrix rows that target store listings reuse one fixture.
  # Reuses the same AppleApp as the tracked-keyword fixture below to avoid
  # duplicate apps under the same organization.
  let(:consistency_apple_app) do
    organization.apple_apps.create!(
      app_store_id: "consistency-spec-#{organization.id}",
      bundle_id: "com.example.consistency.#{organization.id}",
      name: "Consistency App"
    )
  end

  let(:store_listing) do
    organization.store_listings.create!(
      listable: consistency_apple_app,
      locale: "en-US",
      app_name: "Consistency App",
      description: "Spec fixture",
      sync_status: "draft"
    )
  end

  # Lazily build a TrackedKeyword under consistency_apple_app so
  # TrackedKeywordPolicy can resolve the org via `record.apple_app.organization`.
  let(:tracked_keyword) do
    TrackedKeyword.create!(
      apple_app: consistency_apple_app,
      keyword: "consistency kw",
      search_popularity_source: "apple_ads_recommendations"
    )
  end

  # Build a fresh user for each non-owner role so that membership lookups
  # in the policies hit the right row.
  def build_member(role)
    user = User.create!(
      email: "matrix-#{role}-#{SecureRandom.hex(4)}@example.com",
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :free
    )
    organization.memberships.create!(user: user, role: role)
    user
  end

  let(:viewer)    { build_member(:viewer) }
  let(:developer) { build_member(:developer) }
  let(:admin)     { build_member(:admin) }

  def user_for(role)
    case role
    when :owner     then owner
    when :admin     then admin
    when :developer then developer
    when :viewer    then viewer
    else raise "Unknown role: #{role.inspect}"
    end
  end

  # Returns the Pundit verdict for a given matrix key + user + organization.
  # Centralizes which Pundit policy method "owns" each row of the matrix.
  # Raise NotImplementedError for unknown keys so a new matrix row without
  # a corresponding mapping fails loudly rather than silently passing.
  def pundit_verdict_for(key, user, org)
    case key
    when :view_org_data
      OrganizationPolicy.new(user, org).show?
    when :sync_stores
      OrganizationPolicy.new(user, org).sync?
    when :edit_store_listings
      StoreListingPolicy.new(user, store_listing).update?
    when :push_to_stores
      StoreListingPolicy.new(user, store_listing).push?
    when :ai_translate
      StoreListingPolicy.new(user, store_listing).translate?
    when :invite_members
      OrganizationPolicy.new(user, org).invite_members?
    when :create_api_tokens
      OrganizationPolicy.new(user, org).manage_api_tokens?
    when :manage_credentials
      OrganizationPolicy.new(user, org).manage_credentials?
    when :manage_apple_ads_credential
      AppleAdsCredentialPolicy.new(user, org).create?
    when :track_keywords
      TrackedKeywordPolicy.new(user, tracked_keyword).create?
    when :remove_tracked_keywords
      TrackedKeywordPolicy.new(user, tracked_keyword).destroy?
    when :change_member_roles
      OrganizationPolicy.new(user, org).manage_members?
    when :invite_admins
      invitation = OrganizationInvitation.new(organization: org, role: "admin")
      OrganizationInvitationPolicy.new(user, invitation).can_invite_role?(:admin)
    when :delete_store_listings
      StoreListingPolicy.new(user, store_listing).destroy?
    when :view_audit_log
      AuditEventPolicy.new(user, org).index?
    when :delete_organization
      OrganizationPolicy.new(user, org).destroy?
    else
      raise NotImplementedError,
        "No Pundit mapping defined for matrix key #{key.inspect}. Add a " \
        "case in pundit_verdict_for, or list the key in UNGATED_KEYS with a " \
        "justification."
    end
  end

  # Sanity: every matrix row must either appear in MAPPED_KEYS or be
  # explicitly listed in UNGATED_KEYS. This prevents silent matrix drift
  # when someone adds a new capability row.
  it "has a Pundit mapping (or documented exemption) for every matrix row" do
    matrix_keys = helper.permission_matrix.map { |row| row[:key] }
    handled_keys = MAPPED_KEYS + UNGATED_KEYS.keys
    missing = matrix_keys - handled_keys
    expect(missing).to eq([]),
      "These matrix rows have no Pundit mapping and no UNGATED_KEYS entry: " \
      "#{missing.inspect}. Either add a case in pundit_verdict_for AND a " \
      "MAPPED_KEYS entry, or add an UNGATED_KEYS entry documenting why this " \
      "capability has no single Pundit method."
  end

  it "does not have stale MAPPED_KEYS entries for missing rows" do
    matrix_keys = helper.permission_matrix.map { |row| row[:key] }
    extra = MAPPED_KEYS - matrix_keys
    expect(extra).to eq([]),
      "MAPPED_KEYS references keys that are no longer in the matrix: " \
      "#{extra.inspect}. Remove these entries (and the corresponding case " \
      "in pundit_verdict_for)."
  end

  # Walk every (row, role) pair and assert matrix == policy verdict.
  # We aggregate mismatches into a single failure message per role so a
  # single matrix-wide change surfaces all drift in one shot rather than
  # one example failure at a time.
  describe "matrix consistency with Pundit" do
    %i[viewer developer admin owner].each do |role|
      it "matches Pundit policy verdicts for role :#{role}" do
        mismatches = []

        helper.permission_matrix.each do |row|
          key = row[:key]
          next if UNGATED_KEYS.key?(key)
          next unless MAPPED_KEYS.include?(key)

          matrix_value  = row[role]
          policy_value  = pundit_verdict_for(key, user_for(role), organization)

          if matrix_value != policy_value
            mismatches << "  - '#{row[:label]}' (:#{key}): matrix says " \
                          "#{matrix_value}, Pundit returned #{policy_value}"
          end
        end

        expect(mismatches).to be_empty,
          "Matrix-vs-Pundit drift detected for role :#{role}:\n" \
          "#{mismatches.join("\n")}\n\n" \
          "Either update the matrix in PermissionsHelper#permission_matrix or " \
          "update the offending policy method (whichever is wrong). Don't " \
          "silently make them agree without confirming the intended behavior."
      end
    end
  end
end
