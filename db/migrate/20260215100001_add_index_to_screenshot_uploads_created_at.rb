class AddIndexToScreenshotUploadsCreatedAt < ActiveRecord::Migration[8.0]
  def change
    add_index :screenshot_uploads, :created_at
  end
end
