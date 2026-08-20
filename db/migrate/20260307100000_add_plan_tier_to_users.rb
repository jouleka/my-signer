class AddPlanTierToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :plan_tier, :integer, default: 0, null: false
    add_index :users, :plan_tier
  end
end
