class AddLocalesToScreenshotProjects < ActiveRecord::Migration[8.0]
  def change
    add_column :screenshot_projects, :locales, :jsonb, default: [], null: false
  end
end
