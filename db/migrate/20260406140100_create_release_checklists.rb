class CreateReleaseChecklists < ActiveRecord::Migration[8.0]
  def change
    create_table :release_checklists do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :listable_type
      t.bigint :listable_id
      t.string :version_string
      t.string :platform
      t.jsonb :items, null: false, default: []
      t.boolean :all_required_complete, null: false, default: false
      t.jsonb :custom_items, null: false, default: []
      t.references :created_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end

    add_index :release_checklists, [ :organization_id, :listable_type, :listable_id, :version_string ],
              unique: true, name: "idx_release_checklists_org_app_version"
    add_index :release_checklists, [ :organization_id, :platform ],
              name: "idx_release_checklists_org_platform"
  end
end
