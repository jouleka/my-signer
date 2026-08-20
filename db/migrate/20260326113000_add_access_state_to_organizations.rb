class AddAccessStateToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :access_state, :string, null: false, default: "active"
    add_column :organizations, :access_blocked_at, :datetime
    add_column :organizations, :access_block_reason, :string
    add_column :organizations, :access_blocked_by_plan_tier, :string

    add_index :organizations, [ :owner_id, :access_state ]
  end
end
