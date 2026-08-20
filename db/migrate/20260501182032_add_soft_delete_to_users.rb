class AddSoftDeleteToUsers < ActiveRecord::Migration[8.0]
  # `disable_ddl_transaction!` is required by `algorithm: :concurrently`
  # (Postgres rejects CREATE INDEX CONCURRENTLY inside a transaction
  # block). The trade-off is that if any one statement below fails,
  # earlier ones aren't rolled back -- re-running the migration is
  # idempotent thanks to the `if_not_exists` / `column_exists?` guards.
  #
  # Rationale for the concurrent indexes: `users` is one of the largest
  # hot tables in this app, and a non-concurrent `add_index` takes an
  # ACCESS EXCLUSIVE lock for the duration of the build. Even though
  # both columns are mostly NULL on first deploy (so the build is fast),
  # ANY full-table lock on `users` during a deploy can stall every
  # request that touches authentication. Concurrent index builds share
  # a lock with selects/inserts, so the deploy doesn't trip the load
  # balancer's healthcheck.
  disable_ddl_transaction!

  def up
    add_column :users, :deleted_at,     :datetime unless column_exists?(:users, :deleted_at)
    add_column :users, :deletion_token, :string   unless column_exists?(:users, :deletion_token)

    add_index :users, :deleted_at,
              algorithm: :concurrently,
              if_not_exists: true

    add_index :users, :deletion_token,
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :users, :deletion_token, algorithm: :concurrently, if_exists: true
    remove_index :users, :deleted_at,     algorithm: :concurrently, if_exists: true
    remove_column :users, :deletion_token, if_exists: true
    remove_column :users, :deleted_at,     if_exists: true
  end
end
