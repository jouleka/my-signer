require "test_helper"

class PendingDeletionPurgeJobTest < ActiveJob::TestCase
  def make_user(**overrides)
    user = User.new({
      email: "u-#{SecureRandom.hex(6)}@example.test",
      password: "Password123!",
      accepts_terms: "1"
    }.merge(overrides))
    user.skip_confirmation!
    user.save!
    user
  end

  test "destroys users whose deleted_at is older than RETENTION_DAYS" do
    user = make_user
    user.soft_delete!
    user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)
    id = user.id

    PendingDeletionPurgeJob.new.perform

    assert_nil User.find_by(id: id), "user past retention should be hard-deleted"
  end

  test "does NOT destroy users whose deleted_at is within RETENTION_DAYS" do
    user = make_user
    user.soft_delete!
    user.update_column(:deleted_at, 1.day.ago)
    id = user.id

    PendingDeletionPurgeJob.new.perform

    assert_not_nil User.find_by(id: id), "user within retention window must be preserved"
  end

  test "does NOT destroy active (non-deleted) users no matter how old" do
    user = make_user
    user.update_column(:created_at, 5.years.ago)
    id = user.id

    PendingDeletionPurgeJob.new.perform

    assert_not_nil User.find_by(id: id), "active users must never be touched by the purge job"
  end

  test "dry_run logs without destroying" do
    user = make_user
    user.soft_delete!
    user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 5).days.ago)
    id = user.id

    PendingDeletionPurgeJob.new.perform(dry_run: true)

    assert_not_nil User.find_by(id: id), "dry_run must not destroy any user"
  end

  test "is safe across multiple consecutive runs (idempotent)" do
    user = make_user
    user.soft_delete!
    user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)

    PendingDeletionPurgeJob.new.perform
    assert_nothing_raised { PendingDeletionPurgeJob.new.perform }
  end

  test "purge succeeds even when the user owns an org with an asc_build_upload (clears the restrict_with_exception association first)" do
    user = make_user
    org  = Organization.create!(name: "Owned Org #{SecureRandom.hex(4)}", owner: user)
    app  = AppleApp.create!(organization: org, app_store_id: "asc-#{SecureRandom.hex(4)}", bundle_id: "com.test.#{SecureRandom.hex(4)}")
    AscBuildUpload.insert_all([ {
      organization_id: org.id,
      apple_app_id: app.id,
      user_id: user.id,
      remote_id: "r-#{SecureRandom.hex(4)}",
      remote_file_id: "rf-#{SecureRandom.hex(4)}",
      cf_bundle_version: "1",
      cf_bundle_short_version_string: "1.0",
      platform: "iOS",
      file_name: "App.ipa",
      file_size: 100,
      state: "uploaded",
      created_at: Time.current,
      updated_at: Time.current
    } ])

    user.soft_delete!
    user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)
    user_id = user.id
    org_id  = org.id

    PendingDeletionPurgeJob.new.perform

    assert_nil User.find_by(id: user_id), "purge must hard-delete the user past retention"
    assert_nil Organization.find_by(id: org_id), "owned org must cascade-destroy with the user"
    assert_equal 0, AscBuildUpload.where(organization_id: org_id).count,
      "asc_build_uploads must be removed; the restrict_with_exception association cannot block the purge"
  end

  test "purge succeeds for a user who has audit_events as actor (FK on_delete: :nullify clears the reference)" do
    user = make_user
    org  = Organization.create!(name: "AuditOrg #{SecureRandom.hex(4)}", owner: user)
    Audit::Logger.log(
      action: "password_changed",
      actor: user,
      organization: org
    )
    audit_id = AuditEvent.where(actor_id: user.id, action: "password_changed").pick(:id)
    refute_nil audit_id, "audit event must be present before the purge"

    user.soft_delete!
    user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)
    user_id = user.id

    PendingDeletionPurgeJob.new.perform

    assert_nil User.find_by(id: user_id), "purge must succeed even when the user has audit_events"
    surviving = AuditEvent.find_by(id: audit_id)
    refute_nil surviving, "audit event row must survive (preserves the trail)"
    assert_nil surviving.actor_id, "actor_id must be nullified by the FK on_delete: :nullify rule"
  end

  test "purge succeeds when the user owns an org that has notifications belonging to a teammate (notifications cascade-delete with the org)" do
    owner   = make_user
    teammate = make_user
    org = Organization.create!(name: "NotifOrg #{SecureRandom.hex(4)}", owner: owner)
    # No Membership needed — the Notification carries an organization_id
    # FK directly. The bug fires whenever ANY notification row references
    # the org being destroyed, regardless of org membership.
    #
    # Notification on the org belonging to the TEAMMATE — would block the
    # cascade if `Organization` did not declare `has_many :notifications,
    # dependent: :delete_all`. We exercise the path that previously
    # raised ActiveRecord::InvalidForeignKey on
    # notifications.organization_id when the owner was destroyed.
    Notification.create!(
      user: teammate,
      organization: org,
      notification_type: "sync_completed",
      title: "Sync done",
      message: "Sync done"
    )

    owner.soft_delete!
    owner.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)
    owner_id = owner.id
    org_id   = org.id

    PendingDeletionPurgeJob.new.perform

    assert_nil User.find_by(id: owner_id), "owner past retention must be hard-deleted"
    assert_nil Organization.find_by(id: org_id), "owned org must cascade-destroy with the owner"
    assert_equal 0, Notification.where(organization_id: org_id).count,
      "org-scoped notifications must cascade-delete with the org (FK previously blocked the destroy)"
  end

  test "purge succeeds for a user who authored an asc_build_upload in a CO-MEMBERED (third-party) org (FK on_delete: :nullify keeps cascade unblocked)" do
    # Regression: before the FK was switched to ON DELETE NULLIFY,
    # `User#destroy!` raised ActiveRecord::InvalidForeignKey on uploads
    # the user authored in orgs they didn't own — `clear_restricted_associations!`
    # only deletes uploads scoped to the user's OWNED orgs, leaving
    # third-party-org uploads as a poison FK reference. The rescue in
    # `purge_user` would log + report but never actually purge,
    # silently violating the privacy.html.erb 90-day deletion claim.
    deleting_user = make_user(email: "deleting-#{SecureRandom.hex(4)}@example.test")
    third_party_owner = make_user(email: "owner-#{SecureRandom.hex(4)}@example.test")
    # Bump the owner to team tier so a 2nd seat (deleting_user) is
    # allowed by Pricing::PlanEnforcer. The default trial-pro tier
    # caps at 1 seat per org, which would block the membership create
    # below for reasons unrelated to the cascade we're testing.
    third_party_owner.update_columns(plan_tier: User.plan_tiers[:team])
    third_party_org = Organization.create!(name: "Third-Party Org #{SecureRandom.hex(4)}", owner: third_party_owner)
    third_party_org.memberships.create!(user: deleting_user, role: :developer)

    app = AppleApp.create!(
      organization: third_party_org,
      app_store_id: "asc-#{SecureRandom.hex(4)}",
      bundle_id: "com.test.#{SecureRandom.hex(4)}"
    )
    upload = AscBuildUpload.create!(
      organization: third_party_org,
      apple_app: app,
      user: deleting_user,
      remote_id: "r-#{SecureRandom.hex(4)}",
      remote_file_id: "rf-#{SecureRandom.hex(4)}",
      cf_bundle_version: "1",
      cf_bundle_short_version_string: "1.0",
      platform: "iOS",
      file_name: "App.ipa",
      file_size: 100,
      state: "uploaded"
    )

    deleting_user.soft_delete!
    deleting_user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)
    deleting_user_id = deleting_user.id

    PendingDeletionPurgeJob.new.perform

    assert_nil User.find_by(id: deleting_user_id),
      "purge must hard-delete the user even when they authored uploads in a co-membered org"
    surviving_upload = AscBuildUpload.find_by(id: upload.id)
    refute_nil surviving_upload,
      "the upload row must survive (it belongs to the third-party org)"
    assert_nil surviving_upload.user_id,
      "user_id must be nullified by the FK on_delete: :nullify rule"
    refute_nil Organization.find_by(id: third_party_org.id),
      "the third-party org must NOT be destroyed by the purge"
  end

  test "purge succeeds for a user who is the SOLE ADMIN of a co-membered (third-party) org (bypasses prevent_destroy_if_last_admin guard)" do
    # Regression: `Membership` has
    # `before_destroy :prevent_destroy_if_last_admin` which `throw :abort`s
    # when removing the membership would leave the org with zero admins.
    # The guard's intent is UX safety for org-admin actions — but the
    # purge job is a system-initiated 90-day retention cleanup, and an
    # aborted membership cascade raises ActiveRecord::RecordNotDestroyed,
    # which the job's rescue catches and reports silently. Same silent-
    # retention-failure shape as the asc_build_uploads FK bug fixed in
    # 20260507120000. The right behavior is for the cleanup to bypass
    # the guard (the surviving org owner can re-promote an admin later).
    deleting_user = make_user(email: "deleting-admin-#{SecureRandom.hex(4)}@example.test")
    third_party_owner = make_user(email: "tp-owner-#{SecureRandom.hex(4)}@example.test")
    # Bump the owner to team tier so a 2nd seat (the deleting user) is
    # allowed by Pricing::PlanEnforcer. The default trial-pro tier caps
    # at 1 seat per org, which would block the membership create below
    # for reasons unrelated to the guard we're exercising.
    third_party_owner.update_columns(plan_tier: User.plan_tiers[:team])
    third_party_org = Organization.create!(name: "Third-Party Org #{SecureRandom.hex(4)}", owner: third_party_owner)

    # The owner already has the default admin membership (via
    # `after_create :ensure_owner_membership!`). Adding the deleting
    # user as a SECOND admin and then demoting the owner is the way to
    # construct "deleting_user is the SOLE remaining admin from the
    # guard's perspective". Easier path: explicitly create the deleting
    # user's membership as admin, then update the owner's membership
    # to a non-admin role -- the guard counts admins-by-role, not
    # admins-plus-owner.
    third_party_org.memberships.create!(user: deleting_user, role: :admin)
    owner_membership = third_party_org.memberships.find_by!(user: third_party_owner)
    owner_membership.update_columns(role: Membership.roles[:viewer])

    deleting_user.soft_delete!
    deleting_user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)
    deleting_user_id = deleting_user.id

    PendingDeletionPurgeJob.new.perform

    assert_nil User.find_by(id: deleting_user_id),
      "purge must hard-delete the user even when they are the sole admin of a co-membered org"
    refute_nil Organization.find_by(id: third_party_org.id),
      "the third-party org must NOT be destroyed by the purge"
    refute Membership.exists?(user_id: deleting_user_id),
      "the deleting user's membership row must be gone (bypassing prevent_destroy_if_last_admin)"
    # The owner's membership survives. The org now has zero admin-role
    # memberships, but the owner retains org-level control regardless
    # of role — the guard's worst-case-outcome (org has no admin) is
    # acceptable here because the owner is still in charge.
    refute_nil Membership.find_by(id: owner_membership.id),
      "the owner's membership in the third-party org must survive"

    # `Membership.belongs_to :organization, counter_cache: true` means
    # the in-DB `memberships_count` column on Organization is the
    # source of truth for UI badges and the `> 1` gate in
    # `Organization#supports_review_workflow?`. `delete_all` bypasses
    # the counter-cache decrement, so without an explicit
    # `reset_counters` the count would drift by +1 on every
    # co-membered org. Assert it's consistent with the actual count.
    third_party_org.reload
    assert_equal third_party_org.memberships.count, third_party_org.memberships_count,
      "Organization#memberships_count must stay consistent with the actual membership count after the purge"
  end

  test "skips a user whose deleted_at was cleared between query and destroy (race-safe)" do
    # Simulate the race: user appears in the eligible list, but a
    # concurrent restore clears deleted_at before we destroy. The job
    # must re-check inside its transaction and skip rather than destroy
    # a now-active user.
    user = make_user
    user.soft_delete!
    user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)
    id = user.id

    job = PendingDeletionPurgeJob.new
    job.define_singleton_method(:before_destroy_hook) do |target|
      User.where(id: target.id).update_all(deleted_at: nil, deletion_token: nil)
    end

    job.perform

    assert_not_nil User.find_by(id: id),
      "the job's in-transaction recheck must spare a user who was restored mid-run"
  end
end
