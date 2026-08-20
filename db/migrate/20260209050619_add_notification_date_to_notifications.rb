class AddNotificationDateToNotifications < ActiveRecord::Migration[8.0]
  def up
    add_column :notifications, :notification_date, :date

    # Backfill existing rows
    execute <<~SQL
      UPDATE notifications SET notification_date = DATE(created_at)
    SQL

    # Remove duplicates before adding unique index (keep the earliest)
    execute <<~SQL
      DELETE FROM notifications
      WHERE id NOT IN (
        SELECT MIN(id) FROM notifications
        GROUP BY user_id, resource_type, resource_id, notification_type, notification_date
      )
    SQL

    add_index :notifications,
              [ :user_id, :resource_type, :resource_id, :notification_type, :notification_date ],
              unique: true,
              name: "idx_notifications_unique_per_day"
  end

  def down
    remove_index :notifications, name: "idx_notifications_unique_per_day"
    remove_column :notifications, :notification_date
  end
end
