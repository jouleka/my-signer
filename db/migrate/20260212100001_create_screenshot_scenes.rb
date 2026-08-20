class CreateScreenshotScenes < ActiveRecord::Migration[8.0]
  def change
    create_table :screenshot_scenes do |t|
      t.bigint :screenshot_project_id, null: false
      t.integer :position, null: false
      t.string :caption_text
      t.binary :source_image_data
      t.string :source_image_content_type
      t.string :source_image_filename
      t.integer :source_image_width
      t.integer :source_image_height
      t.jsonb :overrides, default: {}
      t.timestamps
      t.index [ :screenshot_project_id, :position ]
      t.index [ :screenshot_project_id ]
    end
    add_foreign_key :screenshot_scenes, :screenshot_projects
  end
end
