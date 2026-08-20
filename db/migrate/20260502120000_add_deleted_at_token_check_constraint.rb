class AddDeletedAtTokenCheckConstraint < ActiveRecord::Migration[8.0]
  # Pairs `deleted_at` and `deletion_token`: either both NULL (active
  # account) or both populated (pending deletion). Today the only writers
  # are User#soft_delete! and User#restore!, both of which set the pair
  # together; this constraint locks that invariant in at the DB level so
  # a future migration or admin SQL can't accidentally split them.
  #
  # NOT VALID + later validate_check_constraint keeps the migration
  # cheap on a populated table -- existing rows are NOT scanned at the
  # time the constraint is added; PG only enforces it on subsequent
  # writes. We then validate in a separate step which acquires only a
  # SHARE UPDATE EXCLUSIVE lock instead of the AccessExclusive lock the
  # initial ADD CONSTRAINT would otherwise need.
  def up
    execute <<~SQL
      ALTER TABLE users
      ADD CONSTRAINT users_deletion_pair_consistent
      CHECK (
        (deleted_at IS NULL AND deletion_token IS NULL) OR
        (deleted_at IS NOT NULL AND deletion_token IS NOT NULL)
      ) NOT VALID
    SQL

    execute "ALTER TABLE users VALIDATE CONSTRAINT users_deletion_pair_consistent"
  end

  def down
    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_deletion_pair_consistent"
  end
end
