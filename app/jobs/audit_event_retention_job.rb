class AuditEventRetentionJob < ApplicationJob
  queue_as :default

  # Retention window for audit events. After this, events are bulk-deleted
  # via delete_all (which bypasses the before_destroy immutability guard on
  # AuditEvent). 365 days gives Team-tier orgs a full year of historical
  # compliance visibility.
  RETENTION_DAYS = 365

  def perform
    cutoff = RETENTION_DAYS.days.ago
    count = AuditEvent.delete_before(cutoff)
    Rails.logger.info("[AuditEventRetention] Deleted #{count} audit events older than #{RETENTION_DAYS} days") if count && count > 0
  end
end
