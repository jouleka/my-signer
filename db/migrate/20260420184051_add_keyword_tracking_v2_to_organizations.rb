class AddKeywordTrackingV2ToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :keyword_tracking_v2, :boolean, default: false, null: false
  end
end
