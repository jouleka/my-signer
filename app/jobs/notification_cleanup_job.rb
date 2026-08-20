class NotificationCleanupJob < ApplicationJob
  queue_as :default

  RETENTION = {
    dismissed: 30.days,
    read: 90.days,
    unread: 365.days
  }.freeze

  def perform
    cleanup_dismissed
    cleanup_read
    cleanup_unread
  end

  private

  def cleanup_dismissed
    count = Notification.where.not(dismissed_at: nil)
                        .where("dismissed_at < ?", RETENTION[:dismissed].ago)
                        .in_batches(of: 1000)
                        .delete_all
    Rails.logger.info("[NotificationCleanup] Deleted #{count} dismissed notifications") if count > 0
  end

  def cleanup_read
    count = Notification.where(dismissed_at: nil)
                        .where.not(read_at: nil)
                        .where("read_at < ?", RETENTION[:read].ago)
                        .in_batches(of: 1000)
                        .delete_all
    Rails.logger.info("[NotificationCleanup] Deleted #{count} read notifications") if count > 0
  end

  def cleanup_unread
    count = Notification.where(dismissed_at: nil, read_at: nil)
                        .where("created_at < ?", RETENTION[:unread].ago)
                        .in_batches(of: 1000)
                        .delete_all
    Rails.logger.info("[NotificationCleanup] Deleted #{count} unread notifications") if count > 0
  end
end
