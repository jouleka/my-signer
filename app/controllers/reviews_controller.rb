class ReviewsController < ApplicationController
  include SanitizesApiErrors

  before_action :authenticate_user!
  before_action :set_org
  before_action :authorize_org_access!
  before_action :require_review_monitoring!, only: [ :reply, :delete_reply, :sync ]
  after_action :verify_authorized

  PER_PAGE = 20

  # GET /organizations/:organization_id/reviews
  def index
    authorize @organization, :show?
    set_current_organization!(@organization)

    @entitlements = @organization.entitlements

    if @entitlements.review_monitoring_enabled?
      load_review_data
    end

    @response_templates = @organization.review_response_templates.ordered
  end

  # POST /organizations/:organization_id/reviews/:id/reply
  def reply
    authorize @organization, :manage_resources?

    review = find_allowed_review!
    return if performed?
    reply_text = params[:reply_text].to_s.strip

    if reply_text.blank?
      return redirect_to organization_reviews_path(@organization),
        alert: "Reply text cannot be blank."
    end

    char_limit = review.reply_char_limit
    if reply_text.length > char_limit
      store_name = review.apple? ? "App Store" : "Google Play"
      return redirect_to organization_reviews_path(@organization),
        alert: "Reply text must be #{char_limit} characters or fewer (#{store_name} limit)."
    end

    review.update!(reply_text: reply_text, reply_status: "pending")

    PostReviewReplyJob.perform_later(app_review_id: review.id)

    redirect_to organization_reviews_path(@organization),
      notice: "Reply queued for posting."
  end

  # DELETE /organizations/:organization_id/reviews/:id/delete_reply
  def delete_reply
    authorize @organization, :manage_resources?

    review = find_allowed_review!
    return if performed?

    unless review.apple? && review.replied?
      return redirect_to organization_reviews_path(@organization),
        alert: "Can only delete replies on Apple reviews that have been posted."
    end

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    raise "No active App Store Connect credential" unless credential

    client = AppStoreConnect::Client.new(credential: credential)

    # Fetch the response ID from Apple
    response_data = client.get("customerReviews/#{review.remote_id}/response")
    response_id = response_data.dig("data", "id")
    raise "No response found on Apple's side" unless response_id

    reviews_service = AppStoreConnect::Reviews.new(client)
    reviews_service.delete_response(response_id: response_id)

    review.update!(reply_text: nil, reply_status: "none", reply_posted_at: nil)

    redirect_to organization_reviews_path(@organization),
      notice: "Reply deleted from App Store."
  rescue StandardError => e
    Rails.logger.error("delete_reply failed: #{e.message}")
    redirect_to organization_reviews_path(@organization),
      alert: "Failed to delete reply: #{safe_error_message(e)}"
  end

  # POST /organizations/:organization_id/reviews/sync
  def sync
    authorize @organization, :manage_resources?

    ReviewSyncJob.perform_later(organization_id: @organization.id)

    redirect_to organization_reviews_path(@organization),
      notice: "Review sync started — data will update shortly."
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def authorize_org_access!
    authorize @organization, :show?
  end

  def require_review_monitoring!
    return if @organization.entitlements.review_monitoring_enabled?

    redirect_to organization_reviews_path(@organization),
      alert: "Review monitoring is not available on your current plan."
  end

  def find_allowed_review!
    entitlements = @organization.entitlements
    max_apps = entitlements.max_review_monitoring_apps
    allowed_apple_ids = @organization.apple_apps.order(:created_at).limit(max_apps).pluck(:id)
    remaining = [ max_apps - allowed_apple_ids.size, 0 ].max
    allowed_android_ids = remaining > 0 ? @organization.android_apps.order(:created_at).limit(remaining).pluck(:id) : []

    review = @organization.app_reviews.find(params[:id])
    allowed = case review.reviewable_type
    when "AppleApp" then allowed_apple_ids.include?(review.reviewable_id)
    when "AndroidApp" then allowed_android_ids.include?(review.reviewable_id)
    else false
    end

    unless allowed
      return redirect_to organization_reviews_path(@organization),
        alert: "This review belongs to an app outside your plan's monitoring limit. Upgrade to manage more apps."
    end

    review
  end

  def load_review_data
    # ── Enforce app limit ─────────────────────────────────────────────
    max_apps = @entitlements.max_review_monitoring_apps
    allowed_apple_ids = @organization.apple_apps.order(:created_at).limit(max_apps).pluck(:id)
    remaining = [ max_apps - allowed_apple_ids.size, 0 ].max
    allowed_android_ids = remaining > 0 ? @organization.android_apps.order(:created_at).limit(remaining).pluck(:id) : []

    total_app_count = @organization.apple_apps.count + @organization.android_apps.count
    @review_app_limit_reached = total_app_count > max_apps

    @reviews = @organization.app_reviews
      .includes(:reviewable)
      .where(reviewable_type: "AppleApp", reviewable_id: allowed_apple_ids)
      .or(@organization.app_reviews.where(reviewable_type: "AndroidApp", reviewable_id: allowed_android_ids))
      .recent

    # App list for filter dropdown (only allowed apps)
    @apple_apps = @organization.apple_apps.where(id: allowed_apple_ids).order(:name)
    @android_apps = @organization.android_apps.where(id: allowed_android_ids).order(:name)

    # Filters
    @app_filter = params[:app].presence
    @platform_filter = params[:platform].presence
    @rating_filter = params[:rating].presence
    @sentiment_filter = params[:sentiment].presence

    # App filter — filter by specific app (e.g., "apple_23" or "android_5")
    if @app_filter
      type, id = @app_filter.split("_", 2)
      if type == "apple" && id.present?
        @reviews = @reviews.where(reviewable_type: "AppleApp", reviewable_id: id)
      elsif type == "android" && id.present?
        @reviews = @reviews.where(reviewable_type: "AndroidApp", reviewable_id: id)
      end
    end

    @reviews = @reviews.by_platform(@platform_filter) if @platform_filter
    @reviews = @reviews.by_rating(@rating_filter) if @rating_filter
    @reviews = @reviews.by_sentiment(@sentiment_filter) if @sentiment_filter

    # Stats (scoped to allowed apps + current filter)
    all_reviews = @organization.app_reviews
      .where(reviewable_type: "AppleApp", reviewable_id: allowed_apple_ids)
      .or(@organization.app_reviews.where(reviewable_type: "AndroidApp", reviewable_id: allowed_android_ids))
    all_reviews = all_reviews.where(reviewable_type: "AppleApp", reviewable_id: @app_filter.split("_", 2).last) if @app_filter&.start_with?("apple_")
    all_reviews = all_reviews.where(reviewable_type: "AndroidApp", reviewable_id: @app_filter.split("_", 2).last) if @app_filter&.start_with?("android_")
    @total_reviews = all_reviews.count
    @average_rating = @total_reviews > 0 ? all_reviews.average(:rating).to_f.round(1) : 0.0
    @negative_count = all_reviews.negative.count
    @unanswered_count = all_reviews.unanswered.count

    # Pagination
    @page = [ params[:page].to_i, 1 ].max
    @total_pages = (@reviews.count.to_f / PER_PAGE).ceil
    @total_pages = 1 if @total_pages < 1
    @reviews = @reviews.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)

    # Rating trend (last 30 days) — scoped to allowed apps + app filter if active
    snapshots_scope = @organization.rating_snapshots
      .where("snapshot_date >= ?", 30.days.ago.to_date)
      .where(snapshotable_type: "AppleApp", snapshotable_id: allowed_apple_ids)
      .or(@organization.rating_snapshots.where("snapshot_date >= ?", 30.days.ago.to_date).where(snapshotable_type: "AndroidApp", snapshotable_id: allowed_android_ids))

    if @app_filter
      type, id = @app_filter.split("_", 2)
      if type == "apple" && id.present?
        snapshots_scope = snapshots_scope.where(snapshotable_type: "AppleApp", snapshotable_id: id)
      elsif type == "android" && id.present?
        snapshots_scope = snapshots_scope.where(snapshotable_type: "AndroidApp", snapshotable_id: id)
      end
    end

    # Group by date and average across apps (handles multi-app "All Apps" view)
    @snapshots = snapshots_scope
                   .group(:snapshot_date)
                   .order(:snapshot_date)
                   .select("snapshot_date, AVG(average_rating) as average_rating")

    # Last sync timestamp (from most recent review or snapshot)
    @last_synced_at = @organization.app_reviews.maximum(:updated_at) ||
                      @organization.rating_snapshots.maximum(:updated_at)

    @summarizations = fetch_summarizations
  end

  def fetch_summarizations
    credential = @organization.app_store_connect_credentials.find_by(active: true)
    return [] unless credential

    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::ReviewSummarizations.new(client)

    apple_app = if @app_filter&.start_with?("apple_")
      @organization.apple_apps.find_by(id: @app_filter.split("_", 2).last)
    else
      @organization.apple_apps.first
    end

    return [] unless apple_app

    Rails.cache.fetch("org:#{@organization.id}:apple_app:#{apple_app.id}:summarizations", expires_in: 1.hour) do
      service.list(app_id: apple_app.app_store_id)
    end
  rescue StandardError => e
    Rails.logger.warn("ReviewsController: Failed to fetch summarizations: #{e.message}")
    []
  end
end
