class AddGranularNotificationPreferencesToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :notify_member_activity, :boolean, default: true, null: false
    add_column :users, :notify_api_token_activity, :boolean, default: true, null: false
    add_column :users, :notify_sso_activity, :boolean, default: true, null: false
    add_column :users, :notify_security_alerts, :boolean, default: true, null: false
    add_column :users, :notify_billing_changes, :boolean, default: true, null: false
    add_column :users, :notify_release_activity, :boolean, default: true, null: false
    add_column :users, :notify_audit_digest, :boolean, default: false, null: false

    User.reset_column_information
    User.where(notify_team_activity: false).update_all(
      notify_member_activity: false,
      notify_api_token_activity: false
    )
  end

  def down
    remove_column :users, :notify_member_activity
    remove_column :users, :notify_api_token_activity
    remove_column :users, :notify_sso_activity
    remove_column :users, :notify_security_alerts
    remove_column :users, :notify_billing_changes
    remove_column :users, :notify_release_activity
    remove_column :users, :notify_audit_digest
  end
end
