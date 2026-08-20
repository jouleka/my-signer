class CreateAppReleases < ActiveRecord::Migration[8.0]
  def change
    create_table :app_releases do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :listable_type, null: false
      t.bigint :listable_id, null: false
      t.string :version_string
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_index :app_releases, [ :organization_id, :listable_type, :listable_id, :version_string ],
              unique: true, name: "idx_app_releases_org_app_version"
    add_index :app_releases, [ :listable_type, :listable_id ], name: "idx_app_releases_listable"
    add_index :app_releases, :status
  end
end
