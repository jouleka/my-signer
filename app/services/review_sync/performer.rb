module ReviewSync
  # Shared review sync logic used by both ReviewSyncJob (background) and
  # ReviewsController#sync (on-demand). Keeps the upsert + notification
  # logic in one canonical place.
  class Performer
    def initialize(organization:, max_apps: nil)
      @organization = organization
      @max_apps = max_apps || organization.entitlements.max_review_monitoring_apps
    end

    # Returns { apps_synced: [...], reviews_found: Integer, errors: [...] }
    def call
      result = { apps_synced: [], reviews_found: 0, errors: [] }

      # Order matters: Apple first, then Android. Both check result[:apps_synced].size
      # against max_apps to enforce the cross-platform app limit.
      sync_apple_reviews(result)
      sync_android_reviews(result)

      result
    end

    private

    attr_reader :organization, :max_apps

    # ── Apple ──────────────────────────────────────────────────────────

    def sync_apple_reviews(result)
      credential = organization.app_store_connect_credentials.find_by(active: true)
      return unless credential

      client = AppStoreConnect::Client.new(credential: credential)
      reviews_service = AppStoreConnect::Reviews.new(client)

      organization.apple_apps.order(:created_at).each do |apple_app|
        break if result[:apps_synced].size >= max_apps

        count = sync_app_reviews_apple(apple_app, reviews_service)
        result[:apps_synced] << { name: apple_app.name, platform: "iOS", reviews: count }
        result[:reviews_found] += count
      rescue StandardError => e
        result[:errors] << "#{apple_app.name}: #{e.message.truncate(100)}"
        Rails.logger.warn("ReviewSync::Performer: Apple failed for #{apple_app.name}: #{e.message}")
      end
    end

    def sync_app_reviews_apple(apple_app, reviews_service)
      reviews_to_upsert = []

      reviews_service.list(app_id: apple_app.app_store_id) do |page|
        (page["data"] || []).each do |review_data|
          attrs = review_data["attributes"] || {}
          reviews_to_upsert << build_apple_review_hash(apple_app, review_data, attrs)
        end
      end

      return 0 if reviews_to_upsert.empty?

      upsert_and_notify(apple_app, reviews_to_upsert)
      reviews_to_upsert.size
    end

    def build_apple_review_hash(apple_app, review_data, attrs)
      {
        organization_id: organization.id,
        reviewable_type: "AppleApp",
        reviewable_id: apple_app.id,
        remote_id: review_data["id"],
        rating: attrs["rating"].to_i,
        title: attrs["title"],
        body: attrs["body"].to_s,
        reviewer_name: attrs["reviewerNickname"],
        territory: attrs["territory"],
        language: nil,
        reviewed_at: attrs["createdDate"] ? Time.zone.parse(attrs["createdDate"]) : Time.current,
        sentiment: ReviewSentiment.classify(rating: attrs["rating"].to_i),
        raw_json: review_data,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # ── Android ────────────────────────────────────────────────────────

    def sync_android_reviews(result)
      gp_credential = organization.google_play_credentials.find_by(active: true)
      return unless gp_credential

      gp_client = GooglePlay::Client.new(credential: gp_credential)
      gp_service = GooglePlay::Reviews.new(gp_client)

      organization.android_apps.order(:created_at).each do |android_app|
        break if result[:apps_synced].size >= max_apps
        count = sync_app_reviews_android(android_app, gp_service)
        result[:apps_synced] << { name: android_app.name, platform: "Android", reviews: count }
        result[:reviews_found] += count
      rescue StandardError => e
        result[:errors] << "#{android_app.name}: #{e.message.truncate(100)}"
        Rails.logger.warn("ReviewSync::Performer: Android failed for #{android_app.name}: #{e.message}")
      end
    end

    def sync_app_reviews_android(android_app, reviews_service)
      response = reviews_service.list(package_name: android_app.package_name, translation_language: "en")
      reviews_list = response.respond_to?(:reviews) ? (response.reviews || []) : []

      reviews_to_upsert = reviews_list.filter_map do |review|
        comment = review.comments&.first
        user_comment = comment&.user_comment
        next unless user_comment

        build_android_review_hash(android_app, review, user_comment)
      end

      return 0 if reviews_to_upsert.empty?

      upsert_and_notify(android_app, reviews_to_upsert)
      reviews_to_upsert.size
    end

    def build_android_review_hash(android_app, review, user_comment)
      {
        organization_id: organization.id,
        reviewable_type: "AndroidApp",
        reviewable_id: android_app.id,
        remote_id: review.review_id,
        rating: user_comment.star_rating.to_i,
        title: nil,
        body: user_comment.text.to_s,
        reviewer_name: review.author_name,
        territory: user_comment.reviewer_language,
        language: user_comment.reviewer_language,
        reviewed_at: user_comment.last_modified&.seconds ? Time.at(user_comment.last_modified.seconds.to_i) : Time.current,
        sentiment: ReviewSentiment.classify(rating: user_comment.star_rating.to_i),
        raw_json: review.to_h.as_json,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # ── Shared ─────────────────────────────────────────────────────────

    def upsert_and_notify(app, reviews_to_upsert)
      existing_ids = app.app_reviews
        .where(remote_id: reviews_to_upsert.map { |r| r[:remote_id] })
        .pluck(:remote_id)

      AppReview.upsert_all(
        reviews_to_upsert,
        unique_by: %i[reviewable_type reviewable_id remote_id]
      )

      # Notify on new negative reviews
      new_negatives = reviews_to_upsert.select { |r| r[:sentiment] == "negative" && !existing_ids.include?(r[:remote_id]) }
      new_negatives.each do |review_attrs|
        review = AppReview.find_by(
          reviewable_type: review_attrs[:reviewable_type],
          reviewable_id: review_attrs[:reviewable_id],
          remote_id: review_attrs[:remote_id]
        )
        ReviewEvents::Notifier.notify_new_review(review) if review
      end
    end
  end
end
