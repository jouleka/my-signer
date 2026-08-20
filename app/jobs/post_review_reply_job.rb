class PostReviewReplyJob < ApplicationJob
  include SanitizesErrorMessage

  queue_as :default
  MAX_ATTEMPTS = 3
  retry_on StandardError, wait: :polynomially_longer, attempts: MAX_ATTEMPTS

  def perform(app_review_id:)
    review = AppReview.find_by(id: app_review_id)
    return unless review
    return unless review.reply_text.present?
    return unless review.reply_status == "pending"

    organization = review.organization

    unless organization.entitlements.review_monitoring_enabled?
      review.update_columns(reply_status: "failed")
      Rails.logger.info("PostReviewReplyJob skipped for AppReview #{app_review_id}: review monitoring not enabled")
      return
    end

    case review.reviewable_type
    when "AppleApp"
      post_apple_reply(review, organization)
    when "AndroidApp"
      post_android_reply(review, organization)
    end
  rescue StandardError => e
    Rails.logger.error("PostReviewReplyJob failed for AppReview #{app_review_id}: #{e.class} - #{sanitize_error_message(e)}")

    # `executions` is the 1-based count of times this job has run. While we still
    # have retries left, re-raise so the declared `retry_on` reschedules the job
    # (otherwise swallowing the error here makes retry_on dead — the first
    # transient failure would permanently mark the reply failed). Only mark the
    # review failed once we've exhausted all attempts.
    if executions < MAX_ATTEMPTS
      raise
    else
      review&.update_columns(reply_status: "failed")
    end
  end

  private

  def post_apple_reply(review, organization)
    credential = organization.app_store_connect_credentials.find_by(active: true)
    raise "No active App Store Connect credential" unless credential

    client = AppStoreConnect::Client.new(credential: credential)
    reviews_service = AppStoreConnect::Reviews.new(client)

    reviews_service.post_response(
      review_id: review.remote_id,
      response_body: review.reply_text
    )

    review.update_columns(reply_status: "posted", reply_posted_at: Time.current)
  end

  def post_android_reply(review, organization)
    credential = organization.google_play_credentials.find_by(active: true)
    raise "No active Google Play credential" unless credential

    client = GooglePlay::Client.new(credential: credential)
    reviews_service = GooglePlay::Reviews.new(client)

    app = review.reviewable
    reviews_service.reply(
      package_name: app.package_name,
      review_id: review.remote_id,
      reply_text: review.reply_text
    )

    review.update_columns(reply_status: "posted", reply_posted_at: Time.current)
  end
end
