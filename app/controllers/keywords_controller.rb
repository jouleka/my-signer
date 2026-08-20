class KeywordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :authorize_org_access!
  before_action :require_keyword_entitlement!, only: [ :suggestions, :append, :competitor_lookup ]
  after_action :verify_authorized

  helper_method :default_country_for_app

  # GET /organizations/:organization_id/keywords
  def index
    authorize @organization, :show?
    set_current_organization!(@organization)

    @entitlements = @organization.entitlements
    @apple_apps = @organization.apple_apps.includes(:store_listings, :tracked_keywords).order(:name)
  end

  # GET /organizations/:organization_id/keywords/:id
  # The id uses "apple_app_42" format, same as ReleasesController.
  def show
    authorize @organization, :show?

    @entitlements = @organization.entitlements
    @app = find_keyword_app
    raise ActiveRecord::RecordNotFound, "App not found" unless @app

    @tab = (params[:tab].presence || "editor").to_s
    @listings_by_locale = @app.store_listings.index_by(&:locale)
    @locales = @listings_by_locale.keys.sort
    @primary_locale = @app.primary_locale || "en-US"
    @current_locale = params[:locale].presence || @primary_locale
    @store_listing = @listings_by_locale[@current_locale]

    # Fallback if primary locale listing doesn't exist
    if @store_listing.nil? && @listings_by_locale.any?
      @store_listing = @listings_by_locale.values.first
      @current_locale = @store_listing.locale
    end

    # Loaded for every tab (rendered before the tab bar) so users always
    # see the degraded-data warning, regardless of which tab they're on.
    # Cheap: two indexed scopes over tracked_keywords.
    @popularity_health = if @entitlements.apple_ads_integration_enabled?
      Aso::PopularityHealth.for(organization: @organization)
    end

    case @tab
    when "tracking"
      load_tracking_data
    when "locale_map"
      load_locale_map_data
    when "suggestions"
      load_suggestions_data
    end
  end

  # GET /organizations/:organization_id/keywords/suggestions
  # JSON proxy to Aso::KeywordSuggestions.
  def suggestions
    authorize @organization, :show?

    term = params[:term].to_s.strip
    country = params[:country].presence || "us"

    raw = Aso::KeywordSuggestions.new(term: term, country: country).fetch
    results = raw.map { |s| Aso::KeywordNormalizer.call(s) }.reject(&:blank?).uniq

    render json: { suggestions: results }
  end

  # PATCH /organizations/:organization_id/keywords/:id/append
  # Appends staged basket keywords to the given StoreListing's keywords field.
  # Row-locks the listing, runs a cheap updated_at staleness check, emits an
  # audit event, and returns a Turbo Stream that refreshes the budget bar and
  # clears the basket zone.
  def append
    authorize @organization, :show?
    @app = find_keyword_app
    raise ActiveRecord::RecordNotFound, "App not found" unless @app

    locale = params[:locale].presence || @app.primary_locale || "en-US"
    submitted_updated_at = params[:store_listing_updated_at].to_s
    # Cap the inbound basket. The Apple keywords field is 100 chars so the
    # realistic ceiling is ~30 short tokens; 200 is a defensive bound that
    # keeps normalization + row-lock windows short even on a rogue client.
    staged_raw = Array(params[:keywords]).first(200)

    listing = nil
    outcome = nil

    StoreListing.transaction do
      listing = @app.store_listings.lock.find_by!(locale: locale)

      if submitted_updated_at.present? &&
         listing.updated_at.iso8601(6) != submitted_updated_at
        outcome = :stale
        raise ActiveRecord::Rollback
      end

      normalized = staged_raw
                     .map { |k| Aso::KeywordNormalizer.call(k) }
                     .reject(&:blank?)

      existing = (listing.keywords || "").split(",").map(&:strip).reject(&:blank?)
      existing_normalized = existing.map { |k| Aso::KeywordNormalizer.call(k) }.to_set
      new_kws = normalized.reject { |k| existing_normalized.include?(k) }.uniq

      if new_kws.empty?
        outcome = :noop
      else
        merged = (existing + new_kws).join(", ")
        listing.keywords = merged

        unless listing.save
          outcome = :invalid
          raise ActiveRecord::Rollback
        end

        outcome = :ok

        Audit::Logger.log(
          action: "store_listing_keywords_updated",
          organization: @organization,
          actor: current_user,
          resource: listing,
          metadata: {
            added_count: new_kws.size,
            final_char_count: listing.keywords.length,
            locale: locale
          },
          request: request
        )
      end
    end

    @store_listing = listing
    @current_locale = locale
    @append_outcome = outcome
    render "keywords/append"
  end

  # POST /organizations/:organization_id/keywords/competitor_lookup
  def competitor_lookup
    authorize @organization, :show?

    app_id  = params[:app_id]
    country = params[:country].presence || "us"

    unless Integer(app_id, exception: false)&.between?(1, 9_999_999_999)
      return render json: { error: "Invalid app_id" }, status: :unprocessable_content
    end

    payload = Aso::CompetitorLookup.new(app_id: app_id, country: country).fetch
    if payload.nil?
      render json: { error: "Couldn't reach Apple — try again in a moment." }, status: :bad_gateway
    else
      render json: payload
    end
  end

  private

  def set_org
    # Scoped to memberships so non-member and non-existent ids both 404 —
    # prevents the 302-vs-404 enumeration oracle that would otherwise
    # expose which org ids exist.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def authorize_org_access!
    authorize @organization, :show?
  end

  def require_keyword_entitlement!
    return if @organization.entitlements.keyword_editor_enabled?

    respond_to do |format|
      format.html do
        redirect_to organization_keywords_path(@organization),
          alert: "Keyword management requires a Pro plan or higher."
      end
      format.json { render json: { error: "Pro plan required for keyword management." }, status: :forbidden }
    end
  end

  def find_keyword_app
    id = params[:id].to_s
    if id.start_with?("apple_app_")
      app_id = id.delete_prefix("apple_app_")
      @organization.apple_apps.find_by(id: app_id)
    end
  end

  def load_tracking_data
    # Intentionally a no-op: the tracking tab partial reads
    # `@app.tracked_keywords` directly and computes the usage/limit banner
    # inline from `@entitlements`. Previously this method populated
    # `@tracked_keywords`, `@rankings`, `@tracking_limit`, and
    # `@tracking_usage`, none of which are consumed by the refactored
    # `_tracking_tab` partial. Left as a stub so the `case` dispatch in
    # `show` remains symmetric with the other tabs.
  end

  def load_locale_map_data
    @locale_map = Aso::LocaleKeywordMap.new(apple_app: @app).build
  end

  # Surfaces Apple's keyword-recommendations (populated by
  # Aso::PopularityRefreshJob) for the current app. Limited to the 20
  # most-popular so the partial stays scannable; callers with a connected
  # credential but zero rows get the empty-state hint in the partial.
  def load_suggestions_data
    @apple_ads_connected = @organization.apple_ads_credential&.last_successful? == true

    @apple_ads_recommendations = if @apple_ads_connected
      @app.apple_ads_recommendations.most_popular.limit(20)
    else
      AppleAdsRecommendation.none
    end

    # Popularity map: normalized_keyword => search_popularity. Consumed by
    # keyword_editor_controller.js to render popularity pips on suggestion
    # chips without a second round-trip.
    @popularity_map = @app.apple_ads_recommendations
                          .pluck(:keyword, :search_popularity)
                          .to_h

    @saved_keyword_ideas = @app.saved_keyword_ideas.order(created_at: :desc).limit(20)
  end

  # Primary locale → two-letter ISO country, lowercased. Falls back to "us"
  # when the locale lacks a region segment (e.g. bare "en"). Used by the
  # Apple Ads recommendations "Track" button to prefill a single country.
  def default_country_for_app(app)
    locale = app.primary_locale
    country = locale.to_s.split("-").last&.downcase
    country.presence || "us"
  end
end
