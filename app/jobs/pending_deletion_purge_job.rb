class PendingDeletionPurgeJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 90

  # Hard-deletes users whose self-initiated soft-delete is older than
  # RETENTION_DAYS. Each candidate is re-checked under a row lock inside
  # a transaction so that a concurrent restore (User#restore!) wins the
  # race and the row is preserved.
  #
  # Pass dry_run: true to log decisions without destroying anything:
  #   PendingDeletionPurgeJob.new.perform(dry_run: true)
  def perform(dry_run: false)
    @dry_run = dry_run

    User.pending_deletion
        .where("deleted_at < ?", RETENTION_DAYS.days.ago)
        .find_each do |candidate|
      purge_user(candidate)
    end
  end

  # Test seam: subclasses/specs can override this to inject behavior just
  # before the destroy fires (used to simulate a mid-run restore race).
  def before_destroy_hook(_user); end

  private

  def purge_user(candidate)
    if @dry_run
      Rails.logger.info("[PendingDeletionPurge] DRY RUN destroy user=#{candidate.id} email=#{candidate.email} deleted_at=#{candidate.deleted_at}")
      return
    end

    User.transaction do
      locked = User.lock.find(candidate.id)

      before_destroy_hook(locked)
      locked.reload

      unless still_eligible?(locked)
        Rails.logger.info("[PendingDeletionPurge] User=#{locked.id} no longer eligible (raced with restore?); skipping")
        next
      end

      clear_restricted_associations!(locked)

      Rails.logger.warn("[PendingDeletionPurge] Destroying user=#{locked.id} email=#{locked.email}")
      locked.destroy!
    end
  rescue ActiveRecord::RecordNotFound
    # Already destroyed by a concurrent run; nothing to do.
  rescue => e
    # Log AND report so the iteration can continue (one stuck user must
    # not block the rest of the daily batch) but the failure surfaces in
    # whatever error tracker subscribes to Rails.error. Without this,
    # missing FK on_delete clauses or a stuck cascade silently fail
    # forever and pile up unprocessed soft-deletions.
    Rails.logger.error("[PendingDeletionPurge] Failed for user=#{candidate.id}: #{e.class} #{e.message}")
    Rails.error.report(
      e,
      handled: true,
      severity: :error,
      context: { job: self.class.name, user_id: candidate.id }
    )
  end

  def still_eligible?(user)
    user.deleted_at.present? && user.deleted_at < RETENTION_DAYS.days.ago
  end

  # Organization#asc_build_uploads is declared `dependent: :restrict_with_exception`
  # to keep day-to-day org admins from accidentally nuking in-flight builds.
  # The purge job is the legitimate cleanup path 90 days after the user
  # explicitly asked for deletion, so we explicitly clear those rows here
  # before the cascade walks Organization#destroy.
  #
  # We also scrub PII out of any AuditEvent rows the user authored. The
  # FK nullifies `actor_id` on user destroy, but the `metadata` jsonb
  # (e.g. `previous_email_domain` from email-change events, or any
  # future field added in a callback path) survives intact and would
  # contradict the email's "permanently deleted" promise. We bypass the
  # AuditEvent before_update immutability guard via `update_all` since
  # this is the equivalent of the existing `delete_before` retention
  # cleanup -- not an in-life mutation.
  def clear_restricted_associations!(user)
    owned_org_ids = user.owned_organizations.pluck(:id)

    # Scope the wipe to the user's OWN orgs. The previous version's
    # second `AscBuildUpload.where(user_id: user.id).delete_all` was
    # unscoped and would silently nuke uploads the user authored in
    # third-party orgs they were just a member of, with no signal to
    # the surviving admins. The single `organization_id IN owned_org_ids`
    # pass below already covers every row that needs to disappear --
    # an upload in the user's own org gets deleted regardless of
    # author; an upload in a co-membered org stays put with the org.
    # As of 20260507120000, asc_build_uploads.user_id is
    # `on_delete: :nullify` so authorship in co-membered orgs is
    # cleared at the FK layer rather than relying on this pre-clean.
    AscBuildUpload.where(organization_id: owned_org_ids).delete_all if owned_org_ids.any?

    # `Membership` has a `before_destroy :prevent_destroy_if_last_admin`
    # callback that `throw :abort`s if removing this member would
    # leave a co-membered org with zero admins. That guard is correct
    # for UI/admin-driven removals -- an org shouldn't lose all its
    # admins by accident. But it is WRONG here: the purge job is a
    # system-initiated 90-day retention cleanup, and an aborted
    # cascade lands in this class's `rescue => e` block, silently
    # blocking the user purge and violating the privacy.html.erb
    # retention claim. The org's surviving owner retains full
    # control regardless of admin-role state, so the right behavior
    # is to bypass the guard for this code path only.
    #
    # `Organization.has_many :memberships, dependent: :delete_all`
    # already SQL-deletes membership rows in the user's OWNED orgs
    # when those orgs cascade-destroy below, so this `delete_all`
    # is primarily about the user's CO-MEMBERED orgs -- where the
    # callback would otherwise fire. Doing it across all the user's
    # memberships is harmless (the owned-org rows would be removed
    # twice, no-op the second time).
    #
    # Capture the co-membered org IDs BEFORE the delete_all so we can
    # `reset_counters` after. `delete_all` is SQL-level and skips the
    # counter-cache decrement on `Membership.belongs_to :organization,
    # counter_cache: true`, which would otherwise leave
    # `organizations.memberships_count` stale by +1 on every co-membered
    # org. Stale counts feed UI badges and the `> 1` check in
    # `Organization#supports_review_workflow?`. We don't bother
    # resetting counters on owned orgs because they're about to be
    # destroyed in the cascade below.
    co_membered_org_ids =
      Membership.where(user_id: user.id)
                .where.not(organization_id: owned_org_ids)
                .pluck(:organization_id)
    Membership.where(user_id: user.id).delete_all
    co_membered_org_ids.each do |org_id|
      Organization.reset_counters(org_id, :memberships)
    end

    AuditEvent.where(actor_id: user.id).update_all(
      metadata: {},
      ip_address: nil,
      user_agent: nil
    )
  end
end
