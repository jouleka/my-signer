class AddSubtitleTextToScreenshotScenes < ActiveRecord::Migration[8.0]
  def change
    add_column :screenshot_scenes, :subtitle_text, :string
  end
end
