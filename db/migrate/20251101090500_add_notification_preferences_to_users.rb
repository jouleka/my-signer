class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.0]
  def change
    change_table :users, bulk: true do |t|
      t.boolean :email_notifications_enabled, default: true, null: false
      t.boolean :notify_certificate_expiry, default: true, null: false
      t.boolean :notify_profile_expiry, default: true, null: false
      t.boolean :notify_keystore_expiry, default: true, null: false
      t.integer :notification_days_before, default: 30, null: false
    end
  end
end
