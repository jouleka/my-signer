class AddBrandSettingsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :brand_settings, :jsonb, default: {}
  end
end
