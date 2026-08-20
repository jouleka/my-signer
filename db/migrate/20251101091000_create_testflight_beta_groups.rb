class CreateTestflightBetaGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :testflight_beta_groups do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :apple_app, null: false, foreign_key: true
      t.string :remote_id, null: false
      t.string :name
      t.boolean :public_link_enabled, default: false, null: false
      t.string :public_link
      t.boolean :is_internal_group, default: false, null: false
      t.integer :tester_count, default: 0, null: false
      t.datetime :created_at_remote
      t.jsonb :raw_json, default: {}

      t.timestamps
    end

    add_index :testflight_beta_groups, [ :organization_id, :remote_id ], unique: true
  end
end
