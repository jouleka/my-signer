class AddMembershipsCounterCacheAndUniqueness < ActiveRecord::Migration[8.0]
  def up
    # 1) Add counter cache column
    add_column :organizations, :memberships_count, :integer, null: false, default: 0

    # 2) Deduplicate memberships before adding unique index
    execute <<~SQL
      DELETE FROM memberships m1
      USING memberships m2
      WHERE m1.id > m2.id
        AND m1.user_id = m2.user_id
        AND m1.organization_id = m2.organization_id;
    SQL

    # 3) Add unique index to enforce uniqueness at DB level
    add_index :memberships, [ :user_id, :organization_id ], unique: true, name: "index_memberships_on_user_and_org_unique"

    # 4) Backfill counter cache values efficiently
    execute <<~SQL
      UPDATE organizations SET memberships_count = sub.count
      FROM (
        SELECT organization_id, COUNT(*) AS count
        FROM memberships
        GROUP BY organization_id
      ) AS sub
      WHERE organizations.id = sub.organization_id;
    SQL
  end

  def down
    remove_index :memberships, name: "index_memberships_on_user_and_org_unique"
    remove_column :organizations, :memberships_count
  end
end
