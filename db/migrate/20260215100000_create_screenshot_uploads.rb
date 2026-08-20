class CreateScreenshotUploads < ActiveRecord::Migration[8.0]
  def change
    create_table :screenshot_uploads do |t|
      t.references :screenshot_project, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :target, null: false
      t.string :status, default: "pending", null: false
      t.jsonb :config, default: {}
      t.jsonb :progress, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :screenshot_uploads, [ :organization_id, :status ]
  end
end
