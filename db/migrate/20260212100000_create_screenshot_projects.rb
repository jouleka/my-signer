class CreateScreenshotProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :screenshot_projects do |t|
      t.bigint :organization_id, null: false
      t.string :name, null: false
      t.string :platform, null: false
      t.jsonb :settings, default: {}
      t.integer :scenes_count, default: 0, null: false
      t.timestamps
      t.index [ :organization_id ]
      t.index [ :organization_id, :name ], unique: true
    end
    add_foreign_key :screenshot_projects, :organizations
  end
end
