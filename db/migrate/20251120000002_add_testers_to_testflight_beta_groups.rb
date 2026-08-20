class AddTestersToTestflightBetaGroups < ActiveRecord::Migration[8.0]
  def change
    add_column :testflight_beta_groups, :testers, :jsonb, default: []
  end
end
