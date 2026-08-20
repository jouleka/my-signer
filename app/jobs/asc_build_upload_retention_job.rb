class AscBuildUploadRetentionJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS   = 90
  ORPHAN_THRESHOLD = 24.hours

  def perform
    AscBuildUpload.terminal
                  .where("created_at < ?", RETENTION_DAYS.days.ago)
                  .in_batches.delete_all

    AscBuildUpload.pending
                  .where("created_at < ?", ORPHAN_THRESHOLD.ago)
                  .in_batches.update_all(state: "abandoned", updated_at: Time.current)
  end
end
