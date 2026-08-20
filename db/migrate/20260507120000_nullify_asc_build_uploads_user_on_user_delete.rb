class NullifyAscBuildUploadsUserOnUserDelete < ActiveRecord::Migration[8.0]
  # PendingDeletionPurgeJob#clear_restricted_associations! deliberately
  # scopes the AscBuildUpload wipe to the user's OWNED organizations
  # (so we don't silently nuke uploads in third-party orgs the user was
  # a member of). That left a gap: a soft-deleted user who authored an
  # upload in a co-membered org has no FK rule to clear authorship at
  # destroy time. The default `add_foreign_key` here was NO ACTION, so
  # `User#destroy!` raises ActiveRecord::InvalidForeignKey for those
  # rows, the purge-job rescue swallows it, and the user never gets
  # purged -- silently violating the privacy.html.erb retention claim.
  #
  # `on_delete: :nullify` mirrors the treatment for the actor columns
  # added in 20260501200739_nullify_user_actor_columns_on_user_delete:
  # the upload row survives, the org admins keep their record of the
  # release event, and the soft-deleted user's user_id is cleared. The
  # AscBuildUpload model is updated in the same change to declare
  # `belongs_to :user, optional: true` so a row with NULL user_id
  # round-trips through validation.
  #
  # Lock-safety: split into NOT VALID + VALIDATE so the existing-row
  # scan happens under SHARE UPDATE EXCLUSIVE (does NOT block writes
  # to `users`) instead of the default SHARE ROW EXCLUSIVE that would
  # block sign-ins for the duration. Same pattern as the actor-columns
  # migration; `disable_ddl_transaction!` is mandatory for that two-
  # phase pattern.
  disable_ddl_transaction!

  def up
    # Drop the NOT NULL constraint on `user_id` first — the FK can only
    # set the column to NULL on cascade if the column actually allows
    # NULL. `change_column_null :null => true` is metadata-only on
    # Postgres (no table rewrite), so it's lock-cheap and safe outside
    # the DDL transaction. New writes from the application still set
    # user_id (the model's create flows always pass a user); only the
    # destroy-time cascade ever leaves it nil.
    change_column_null :asc_build_uploads, :user_id, true

    remove_foreign_key :asc_build_uploads, column: :user_id, if_exists: true
    add_foreign_key :asc_build_uploads, :users, column: :user_id, on_delete: :nullify, validate: false
    validate_foreign_key :asc_build_uploads, column: :user_id
  end

  def down
    # Order matters. Restore the NOT NULL constraint FIRST, because if
    # the forward migration has already nullified any row via the
    # cascade, `change_column_null ..., false` will raise and we want
    # that failure to happen BEFORE we touch the FK rule. Otherwise
    # we'd land in a half-rollback: FK swapped back to restrictive
    # NO ACTION, but the column still nullable -- and the next call to
    # PendingDeletionPurgeJob would start raising InvalidForeignKey
    # again (the exact bug the forward migration fixes).
    #
    # Operators who need to roll back with NULLs present must first
    # backfill or delete those rows, or update this migration to
    # explicitly choose a policy.
    change_column_null :asc_build_uploads, :user_id, false

    remove_foreign_key :asc_build_uploads, column: :user_id, if_exists: true
    add_foreign_key :asc_build_uploads, :users, column: :user_id, validate: false
    validate_foreign_key :asc_build_uploads, column: :user_id
  end
end
