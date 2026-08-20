class NullifyUserActorColumnsOnUserDelete < ActiveRecord::Migration[8.0]
  # When a User row is hard-deleted (currently only via PendingDeletionPurgeJob
  # 90 days after a self-initiated soft-delete), Postgres FK constraints with
  # the default NO ACTION rule reject the DELETE. The Rails-side
  # `belongs_to :actor, optional: true` semantics already match nullification
  # for these "actor" / "author" columns — the records survive without an
  # author, the audit trail just shows nil. Aligning the DB-level FK to
  # `on_delete: :nullify` makes the cascade actually work and matches the
  # treatment already in place for `audit_events.organization_id` and
  # `saved_keyword_ideas.added_by_user_id`.
  #
  # Lock-safety: a default `add_foreign_key` validates the constraint
  # immediately, which scans every referencing row AND takes a SHARE
  # ROW EXCLUSIVE lock on `users` for the duration of the scan. On a hot
  # `users` table that blocks every authenticated request (sign-in,
  # session refresh) for the duration of the scan. We split the FK
  # creation into two phases:
  #   1) `add_foreign_key ..., validate: false` — adds the constraint
  #      WITHOUT scanning existing rows; takes only a brief
  #      ACCESS EXCLUSIVE lock on the referencing table. New writes are
  #      enforced from this moment on.
  #   2) `validate_foreign_key` — validates existing rows under a
  #      SHARE UPDATE EXCLUSIVE lock that does NOT block sign-ins.
  # Mirrors the existing safe pattern used in
  # 20260502120000_add_deleted_at_token_check_constraint.rb.
  #
  # `disable_ddl_transaction!` is required because `validate_foreign_key`
  # cannot run inside the same transaction that added the constraint
  # in NOT VALID state.
  disable_ddl_transaction!

  TARGETS = [
    [ :audit_events,        :actor_id ],
    [ :release_checklists,  :created_by_id ],
    [ :release_notes,       :created_by_id ],
    [ :release_notes,       :reviewed_by_id ]
  ].freeze

  def up
    TARGETS.each do |table, column|
      remove_foreign_key table, column: column, if_exists: true
      add_foreign_key table, :users, column: column, on_delete: :nullify, validate: false
      validate_foreign_key table, column: column
    end
  end

  def down
    TARGETS.each do |table, column|
      remove_foreign_key table, column: column, if_exists: true
      add_foreign_key table, :users, column: column, validate: false
      validate_foreign_key table, column: column
    end
  end
end
