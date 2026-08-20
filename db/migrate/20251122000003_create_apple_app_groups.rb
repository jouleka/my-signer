class CreateAppleAppGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :apple_app_groups do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :identifier, null: false       # group.com.example.app
      t.string :name
      t.string :team_id
      t.timestamps
    end

    add_index :apple_app_groups, [ :organization_id, :identifier ], unique: true
    add_index :apple_app_groups, [ :organization_id, :team_id ]

    # Join table for Bundle ID associations
    create_table :apple_bundle_id_app_groups do |t|
      t.references :apple_bundle_id, null: false, foreign_key: true
      t.references :apple_app_group, null: false, foreign_key: true
      t.timestamps
    end

    add_index :apple_bundle_id_app_groups, [ :apple_bundle_id_id, :apple_app_group_id ],
              unique: true, name: 'idx_bundle_app_group_unique'
  end
end
