class AddUniqueIndexToNotifications < ActiveRecord::Migration[8.0]
  def change
    add_index :notifications,
              %i[user_id resource_type resource_id notification_type notification_date],
              unique: true,
              where: "notification_date IS NOT NULL AND resource_type IS NOT NULL AND resource_id IS NOT NULL",
              name: "index_notifications_on_dedup_key"
  end
end
