class AddLocaleVariantsToScreenshotScenes < ActiveRecord::Migration[8.0]
  def change
    add_column :screenshot_scenes, :locale_variants, :jsonb, default: {}, null: false
  end
end
