class EnhanceNotificationsForNewTypes < ActiveRecord::Migration[8.0]
  def change
    # Allow nullable resource columns for notification types that don't reference a specific resource
    change_column_null :notifications, :resource_type, true
    change_column_null :notifications, :resource_id, true
    change_column_null :notifications, :organization_id, true

    # New user notification preferences
    add_column :users, :notify_sync_failures, :boolean, default: true, null: false
    add_column :users, :notify_sync_changes, :boolean, default: false, null: false
    add_column :users, :notify_revocations, :boolean, default: true, null: false
    add_column :users, :notify_team_activity, :boolean, default: true, null: false
  end
end
