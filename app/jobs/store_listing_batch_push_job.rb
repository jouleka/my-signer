class StoreListingBatchPushJob < ApplicationJob
  queue_as :default

  # Google Play edits for the same app must complete sequentially. Each locale
  # records its own result, and a failed locale does not prevent the rest.
  #
  # Listings are marked "pushing" by the controller before enqueueing. If this
  # job dies before a listing reports back, the ensure block marks leftovers
  # as failed; if the process is killed outright, StoreListing's 15-minute
  # staleness rule releases the lock instead.
  def perform(organization_id:, store_listing_ids:)
    @heartbeat_at = Time.current
    store_listing_ids.each_with_index do |id, index|
      heartbeat!(store_listing_ids.drop(index))
      StoreListingPushJob.perform_now(organization_id: organization_id, store_listing_id: id)
    end
  ensure
    release_unfinished!(store_listing_ids)
  end

  private

  # Keeps listings still waiting in this batch from looking stale while
  # earlier locales are being pushed.
  def heartbeat!(remaining_ids)
    @heartbeat_at = Time.current
    StoreListing.where(id: remaining_ids, push_status: "pushing").update_all(updated_at: @heartbeat_at)
  end

  # Only touch rows this run could have written: a newer push can start only
  # once this run's rows went stale, so anything updated after
  # heartbeat + PUSH_STALE_AFTER belongs to that newer push.
  def release_unfinished!(store_listing_ids)
    return if store_listing_ids.blank?

    cutoff = (@heartbeat_at || Time.current) + StoreListing::PUSH_STALE_AFTER
    StoreListing.where(id: store_listing_ids, push_status: "pushing", updated_at: ..cutoff)
      .update_all(push_status: "failed", push_error: StoreListing::PUSH_INTERRUPTED_MESSAGE, updated_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("StoreListingBatchPushJob: could not release unfinished listings - #{e.class}: #{e.message}")
  end
end
