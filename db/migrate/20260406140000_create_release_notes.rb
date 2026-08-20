class CreateReleaseNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :release_notes do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :listable_type, null: false
      t.bigint :listable_id, null: false
      t.string :version_string
      t.string :build_number
      t.string :status, null: false, default: "draft"
      t.string :locale, null: false, default: "en-US"
      t.jsonb :template_data, null: false, default: {}
      t.text :rendered_text
      t.text :raw_input
      t.string :source
      t.jsonb :translations, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.datetime :applied_at
      t.datetime :published_at

      t.timestamps
    end

    add_index :release_notes, [ :organization_id, :listable_type, :listable_id, :status ],
              name: "idx_release_notes_org_app_status"
    add_index :release_notes, [ :listable_type, :listable_id, :version_string ],
              name: "idx_release_notes_app_version"
    add_index :release_notes, :status
  end
end
