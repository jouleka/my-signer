class CreateScreenshotExports < ActiveRecord::Migration[8.0]
  def change
    create_table :screenshot_exports do |t|
      t.references :screenshot_project, null: false, foreign_key: true
      t.string :resolution, null: false            # e.g. "1320x2868"
      t.integer :scene_position, null: false       # matches screenshot_scenes.position
      t.string :locale, null: false, default: ""     # e.g. "en-US", "" for non-locale exports
      t.string :export_format, default: "standard" # "standard" or "fastlane"

      t.timestamps
    end

    add_index :screenshot_exports,
              [ :screenshot_project_id, :resolution, :scene_position, :locale ],
              unique: true,
              name: "idx_screenshot_exports_unique_key"
  end
end
