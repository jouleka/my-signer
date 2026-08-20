class AddAiRewritesTrackingToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :ai_rewrites_count, :integer, null: false, default: 0
    add_column :organizations, :ai_rewrites_reset_at, :datetime
  end
end
