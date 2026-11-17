class ReleasesController < ApplicationController
  ALLOWED_TRANSLATION_FIELDS = %w[app_name subtitle keywords description promotional_text short_description].freeze

  before_action :authenticate_user!
  before_action :set_org
  before_action :resolve_release, only: %i[show update sync sync_status push translate add_locale create_listing
                                            update_release_note translate_release_note rewrite_release_note
                                            fetch_commits submit_for_review approve_review reject_review
                                            create_release_note destroy_release_note update_release_translation apply_release_note
                                            submit_to_store refresh_validation_errors]
  after_action :verify_authorized

  # GET /organizations/:organization_id/releases
  def index
    authorize @organization, :show?
    set_current_organization!(@organization)

    @apple_apps = @organization.apple_apps.includes(:store_listings, :app_store_versions).order(:name)
    @android_apps = @organization.android_apps.includes(:store_listings, :play_store_releases).order(:name)
    @entitlements = @organization.entitlements

    if @organization.supports_review_workflow?
      @pending_review_count = @organization.release_notes.where(status: "pending_review").count
      @pending_review_notes = @organization.release_notes.where(status: "pending_review").includes(:listable)
    end
  end

  # GET /organizations/:organization_id/releases/:id
  # The main release dashboard for an app — tabbed interface with all sub-resources.
  def show
    authorize @organization, :show?

    @entitlements = @organization.entitlements
    @app_release = find_or_create_app_release
    @tab = (params[:tab].presence || default_tab).to_s
    @subtab = params[:subtab].presence

    @listings_by_locale = @app.store_listings.index_by(&:locale)
    @locales = @listings_by_locale.keys.sort
    @primary_locale = primary_locale_for(@app)
    @current_locale = params[:locale].presence || @primary_locale
    @store_listing = @listings_by_locale[@current_locale]

    # Fallback: if the requested/primary locale has no listing but other locales
    # do exist, show the first available one instead of an empty state. This
    # handles apps whose Apple primaryLocale isn't en-US (e.g., en-GB) and apps
    # where only one locale has been synced so far.
    if @store_listing.nil? && @listings_by_locale.any?
      @store_listing = @listings_by_locale.values.first
      @current_locale = @store_listing.locale
    end

    @release_note = current_release_note
    @checklist = ensure_checklist!
    @push_status = StoreListingSync::PushStatus.for(@app)
    @sync_operation = StoreListingSync::OperationStatus.new(@app).read
  end

  # PATCH /organizations/:organization_id/releases/:id
  # Updates the StoreListing fields for the current locale (Listing tab).
  def update
    # Edit store listings: developer or higher (viewers blocked).
    authorize @organization, :manage_resources?

    @entitlements = @organization.entitlements
    @listings_by_locale = @app.store_listings.index_by(&:locale)
    @locales = @listings_by_locale.keys.sort
    @primary_locale = primary_locale_for(@app)
    @current_locale = params[:locale].presence || @primary_locale
    @store_listing = @listings_by_locale[@current_locale]

    unless @store_listing
      return redirect_to organization_release_path(@organization, params[:id], tab: "listing"),
        alert: "No store listing found for locale #{@current_locale}."
    end

    if @store_listing.with_lock { @store_listing.update(store_listing_params) }
      # User just saved content on a listing that was flagged "needs_review"
      # by the AI translator. A manual save means they reviewed (or
      # intentionally edited) — drop the flag so the yellow dot in the
      # locale tab bar goes away.
      if @store_listing.translation_status == "needs_review"
        @store_listing.update_column(:translation_status, "approved")
      end
      respond_to do |format|
        format.html {
          redirect_to organization_release_path(@organization, params[:id], tab: "listing", locale: @current_locale),
            notice: "Listing saved."
        }
        # Autosave path — no render, no redirect. The client's indicator flips
        # to "Saved" on a 2xx response.
        format.turbo_stream { head :ok }
      end
    else
      # Validation failure — log the full error list so it's visible in the
      # dev log when autosave appears to silently "revert" a field. When the
      # form submits all fields, a single too-long field rejects the whole
      # save and the user's last edit is lost (pre-edit value stays in DB).
      Rails.logger.warn(
        "StoreListing update failed for listing=#{@store_listing.id} locale=#{@store_listing.locale}: " \
        "#{@store_listing.errors.full_messages.to_sentence}"
      )
      respond_to do |format|
        format.turbo_stream do
          # Return validation errors as JSON in the body so the client can
          # surface them (the autosave fetch reads response.ok + body).
          render json: { errors: @store_listing.errors.full_messages }, content_type: "application/json",
                 status: :unprocessable_content
        end
        format.html do
          @app_release = find_or_create_app_release
          @tab = "listing"
          @release_note = current_release_note
          @checklist = ensure_checklist!
          render :show, status: :unprocessable_content
        end
      end
    end
  end

  # POST /organizations/:organization_id/releases/:id/sync
  def sync
    # Sync from stores: developer or higher (viewers blocked).
    authorize @organization, :sync?

    status = StoreListingSync::OperationStatus.new(@app)
    @app.with_lock do
      if @app.store_listings.push_in_progress.exists?
        return push_error_response("A push is already in progress. Wait for it to finish before syncing.")
      end
      unless status.active?
        operation = status.start
        StoreListingSyncJob.perform_later(
          organization_id: @organization.id, listable_type: @app.class.name,
          listable_id: @app.id, operation_id: operation[:id]
        )
      end
    end

    respond_to do |format|
      format.html { redirect_to organization_release_path(@organization, params[:id]), notice: "Sync started. The page will refresh when complete." }
      format.json { render json: { status: "enqueued", operation: status.read }, status: :accepted }
    end
  end

  # GET /organizations/:organization_id/releases/:id/sync_status
  def sync_status
    authorize @organization, :show?

    primary_listing = @app.store_listings.find_by(locale: primary_locale_for(@app)) || @app.store_listings.first

    # Submission status is sourced from the latest AppStoreVersion (iOS only).
    # The Stimulus controller polls this endpoint after a submission is enqueued
    # to detect transitions: "submitting" → "submitted" / "failed".
    version = find_or_create_app_release.platform_release if @app.is_a?(AppleApp)

    render json: {
      sync_status: primary_listing&.sync_status || "unknown",
      sync_operation: StoreListingSync::OperationStatus.new(@app).read,
      last_synced_at: primary_listing&.last_synced_at&.iso8601,
      locale_count: @app.store_listings.count,
      submission_status: version&.submission_status || "idle",
      submission_error: version&.submission_error,
      app_store_state: version&.app_store_state
    }.merge(StoreListingSync::PushStatus.for(@app))
  end

  # POST /organizations/:organization_id/releases/:id/push
  # The unified Push action: applies any draft release note to the StoreListing,
  # then enqueues StoreListingPushJob to send everything to the store.
  def push
    # Push to store: developer or higher (viewers blocked).
    authorize @organization, :manage_resources?

    unless @organization.entitlements.store_listing_push_enabled?
      return handle_push_upgrade_required
    end

    @app_release = find_or_create_app_release

    primary_listing = @app.store_listings.find_by(locale: primary_locale_for(@app)) || @app.store_listings.first
    unless primary_listing
      return push_error_response("No store listing found for this app. Sync from the store first.")
    end

    # Pending-review guard: refuse to push if there's a release note awaiting review
    primary_note = @app_release.primary_release_note
    if primary_note&.review_required?
      return push_error_response(
        "What's New is awaiting approval. Approve it before pushing, or wait for an admin to approve.",
        tab: "whats_new"
      )
    end

    return push_error_response("Wait for the release note AI operation to finish.", tab: "whats_new") if primary_note&.ai_pending?

    # Auto-detected blocker guard: refuse push if any required auto-detected error exists.
    return if blocking_checklist_issues_redirect!(action_verb: "push")

    pushed_listing_ids = []
    @app.with_lock do
      if @app.store_listings.push_in_progress.exists? || StoreListingSync::OperationStatus.new(@app).active?
        return push_error_response("A store operation is already in progress. Wait for it to finish before pushing.")
      end
      if primary_note && primary_note.status != "applied" && primary_note.content_editable? && primary_note.rendered_text.present?
        primary_note.apply_to_store_listings!
      end
      pushed_listing_ids = @app.store_listings.order(:id).pluck(:id)
      @app.store_listings.mark_pushing!
      StoreListingBatchPushJob.perform_later(organization_id: @organization.id, store_listing_ids: pushed_listing_ids)
    end

    # Audit: iOS pushes = store_listing_pushed, Android pushes = play_store_pushed.
    # The App Store vs Play Store distinction matches the ACTIONS enum in AuditEvent.
    push_action = @app.is_a?(AppleApp) ? "store_listing_pushed" : "play_store_pushed"
    Audit::Logger.log(
      action: push_action,
      actor: current_user,
      organization: @organization,
      resource: @app_release,
      metadata: {
        app_id: @app.id,
        app_type: @app.class.name,
        listings_count: pushed_listing_ids.size
      },
      request: request
    )

    respond_to do |format|
      format.html { redirect_to organization_release_path(@organization, params[:id]), notice: "Push started. Changes are being sent to the store." }
      format.json { render json: { status: "enqueued" }, status: :accepted }
    end
  rescue ActiveRecord::RecordInvalid, RuntimeError => e
    push_error_response(ErrorMessageSanitizer.sanitize(e), tab: "whats_new")
  end

  # POST /organizations/:organization_id/releases/:id/submit_to_store
  # Submits the latest iOS App Store version for review via Apple's reviewSubmissions API.
  # All work happens in AppStoreSubmitJob; the Stimulus controller polls sync_status
  # for the transient "submitting" → "submitted"/"failed" transition.
  def submit_to_store
    # Submit to App Store: developer or higher (viewers blocked).
    authorize @organization, :manage_resources?

    unless @app.is_a?(AppleApp)
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "Submission to the store is only supported for iOS apps today."
    end

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "No active App Store Connect credential. Add one in Settings first."
    end

    version = find_or_create_app_release.platform_release
    unless version
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "No App Store version found. Sync from the store to fetch the latest version."
    end

    unless version.submittable?
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "Version v#{version.version_string} is #{version.app_store_state&.titleize} and can't be submitted right now."
    end

    unless version.apple_build_id.present?
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "No build attached to version v#{version.version_string}. Attach a build in App Store Connect, then sync from the store."
    end

    primary_note = find_or_create_app_release.primary_release_note
    if primary_note&.review_required? || primary_note&.ai_pending?
      return redirect_to organization_release_path(@organization, params[:id], tab: "whats_new"),
        alert: "Resolve the release note review or AI operation before submitting."
    end

    # Auto-detected blocker guard: shared with the push action.
    return if blocking_checklist_issues_redirect!(action_verb: "submit")

    release_type = params[:release_type].to_s.presence || "AFTER_APPROVAL"
    unless %w[AFTER_APPROVAL MANUAL SCHEDULED].include?(release_type)
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "Invalid release type."
    end

    earliest_release_date_iso = nil
    if release_type == "SCHEDULED"
      parsed = begin
        Time.zone.parse(params[:earliest_release_date].to_s)
      rescue ArgumentError
        nil
      end

      unless parsed && parsed > 1.hour.from_now
        return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
          alert: "Scheduled release date must be at least 1 hour in the future."
      end
      earliest_release_date_iso = parsed.utc.iso8601
    end

    # Atomic check-and-set: claim_submission! does a single UPDATE ... WHERE
    # NOT submitting, so two concurrent requests can't both pass the guard.
    unless version.claim_submission!
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "A submission is already in progress for this version."
    end

    begin
      AppStoreSubmitJob.perform_later(
        organization_id: @organization.id,
        app_store_version_id: version.id,
        release_type: release_type,
        earliest_release_date: earliest_release_date_iso
      )
    rescue StandardError => e
      # If enqueue fails (Redis unreachable, queue misconfigured, etc.), release
      # the claim so the user can retry — otherwise the version is stuck showing
      # "Submitting…" forever.
      version.update_columns(submission_status: nil, submission_error: nil)
      Rails.logger.error("Failed to enqueue AppStoreSubmitJob: #{e.class} - #{e.message}")
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "Could not start submission: #{ErrorMessageSanitizer.sanitize(e)}. Please try again."
    end

    Audit::Logger.log(
      action: "release_submitted",
      actor: current_user,
      organization: @organization,
      resource: version,
      metadata: {
        app_id: @app.id,
        version: version.version_string,
        release_type: release_type,
        earliest_release_date: earliest_release_date_iso
      },
      request: request
    )

    redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
      notice: "Submitting v#{version.version_string} to the App Store for review."
  end

  # POST /organizations/:organization_id/releases/:id/refresh_validation_errors
  # Synchronously re-fetches Apple's validation errors for the latest version
  # and stores them in the version's `issues` JSONB column so the submission
  # tab's error panel can render fresh data without waiting for the next sync.
  def refresh_validation_errors
    # Mutates DB by saving fresh validation errors -- treat as a write.
    authorize @organization, :manage_resources?

    unless @app.is_a?(AppleApp)
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission")
    end

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "No active App Store Connect credential."
    end

    version = find_or_create_app_release.platform_release
    unless version&.version_id.present?
      return redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "No version found to refresh."
    end

    begin
      client = AppStoreConnect::Client.new(credential: credential)
      versions_service = AppStoreConnect::Versions.new(client)
      errors = versions_service.validation_errors(version_id: version.version_id)
      version.update_issues_from_apple_errors!(errors)
      redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        notice: errors.any? ? "Refreshed. Apple reported #{errors.size} issue(s)." : "Refreshed. No issues reported by Apple."
    rescue StandardError => e
      Rails.logger.error("Failed to refresh validation errors: #{e.class} - #{e.message}")
      redirect_to organization_release_path(@organization, params[:id], tab: "submission"),
        alert: "Failed to refresh validation errors: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  # POST /organizations/:organization_id/releases/:id/translate
  # Translates the current store listing locale from the base locale.
  def translate
    # AI translate: developer or higher (viewers blocked).
    authorize @organization, :manage_resources?

    @entitlements = @organization.entitlements
    unless @entitlements.ai_translations_remaining(@organization) > 0
      return redirect_to organization_release_path(@organization, params[:id], tab: "listing"),
        alert: "You've reached your monthly AI translation limit."
    end

    target_locale = params[:locale].to_s.strip
    target_listing = @app.store_listings.find_by(locale: target_locale)
    base_listing = @app.store_listings.find_by(locale: params[:base_locale] || primary_locale_for(@app))

    if target_listing.nil? || base_listing.nil? || target_listing.id == base_listing.id
      return redirect_to organization_release_path(@organization, params[:id], tab: "listing"),
        alert: "Cannot translate: invalid base or target locale."
    end

    target_listing.with_lock do
      unless target_listing.translation_pending?
        operation_id = SecureRandom.uuid
        target_listing.update!(translation_status: "pending", metadata: target_listing.metadata
          .except("translation_error").merge("translation_operation_id" => operation_id))
        StoreListingTranslationJob.perform_later(
          organization_id: @organization.id,
          store_listing_id: target_listing.id,
          base_listing_id: base_listing.id,
          fields: permitted_translation_fields,
          operation_id: operation_id
        )
      end
    end

    respond_to do |format|
      # Turbo path: swap the AI Translate button for a "Translating…" pill.
      # The job's trigger_live_refresh broadcasts a refresh when done; the page
      # morphs and the button returns to idle with translated fields below.
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "ai-translate-listing-button",
          partial: "releases/ai_translate_listing_button",
          locals: { pending: true, has_reference: true }
        )
      end
      format.html do
        redirect_to organization_release_path(@organization, params[:id], tab: "listing", locale: target_locale),
          notice: "Translation started."
      end
    end
  end

  # POST /organizations/:organization_id/releases/:id/add_locale
  def add_locale
    # Add store listing locale: edit operation, developer or higher.
    authorize @organization, :manage_resources?

    locale = params[:locale].to_s.strip
    return unless validate_listing_locale(locale)

    @app.with_lock do
      if @app.store_listings.exists?(locale: locale)
        return redirect_to organization_release_path(@organization, params[:id], tab: "listing", locale: locale),
          notice: "Locale #{locale} already exists."
      end

      current_count = @app.store_listings.count
      max_locales = @organization.entitlements.max_store_listing_locales
      if current_count >= max_locales
        return redirect_to organization_release_path(@organization, params[:id], tab: "listing"),
          alert: "You've reached your limit of #{max_locales} locale(s) on the #{@organization.plan_tier.titleize} plan."
      end

      listing = @app.store_listings.new(organization: @organization, locale: locale, sync_status: "draft")
      if listing.save
        redirect_to organization_release_path(@organization, params[:id], tab: "listing", locale: locale),
          notice: "Locale #{locale} added."
      else
        redirect_to organization_release_path(@organization, params[:id], tab: "listing"),
          alert: listing.errors.full_messages.to_sentence
      end
    end
  end

  # POST /organizations/:organization_id/releases/:id/create_listing
  # Creates a new initial store listing for an app that has none yet.
  def create_listing
    # Create store listing: developer or higher (viewers blocked).
    authorize @organization, :manage_resources?

    locale = (params[:locale].presence || primary_locale_for(@app)).to_s.strip
    return unless validate_listing_locale(locale)

    @app.with_lock do
      if @app.store_listings.exists?
        return redirect_to organization_release_path(@organization, params[:id], tab: "listing"),
          notice: "Store listings already exist for this app."
      end

      listing = @app.store_listings.new(organization: @organization, locale: locale, sync_status: "draft")
      if listing.save
        redirect_to organization_release_path(@organization, params[:id], tab: "listing", locale: locale),
          notice: "Initial store listing created. Sync from the store to populate fields."
      else
        redirect_to organization_release_path(@organization, params[:id], tab: "listing"),
          alert: listing.errors.full_messages.to_sentence
      end
    end
  end

  # ── What's New tab actions ───────────────────────────────────────

  # POST /organizations/:organization_id/releases/:id/release_notes
  def create_release_note
    # Create release note: developer or higher (viewers blocked).
    authorize @organization, :manage_resources?

    rn = @organization.release_notes.build(release_note_params)
    rn.listable = @app
    rn.locale = primary_locale_for(@app) if params.dig(:release_note, :locale).blank?
    rn.status ||= "draft"
    rn.source ||= "manual"
    rn.template_data ||= { "new" => [], "improved" => [], "fixed" => [] }
    rn.created_by = current_user

    if rn.save
      redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: rn.id),
        notice: "Release note created."
    else
      redirect_to organization_release_path(@organization, params[:id], tab: "whats_new"),
        alert: rn.errors.full_messages.to_sentence
    end
  rescue JSON::ParserError, TypeError
    release_note_save_error([ "Template data must be valid JSON." ])
  end

  # PATCH /organizations/:organization_id/releases/:id/release_notes/:note_id
  def update_release_note
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :update?

    attributes = release_note_params
    if note.with_lock { authorize note, :update?; note.update(attributes) }
      respond_to do |format|
        format.turbo_stream { render json: note.slice(:status, :review_decision).merge(review_required: note.review_required?), content_type: "application/json" }
        format.html { redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id), notice: "Release note saved." }
      end
    else
      release_note_save_error(note.errors.full_messages)
    end
  rescue JSON::ParserError, TypeError
    release_note_save_error([ "Template data must be valid JSON." ])
  end

  # PATCH .../release_notes/:note_id/translations/:locale
  # Used by the locale-switcher autosave to update a single translation entry in
  # `release_note.translations` (a JSONB hash keyed by BCP-47 locale).
  def update_release_translation
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :update?

    locale = params[:locale].to_s.strip
    text = params[:translated_text].to_s
    unless locale.match?(ReleaseNote::LOCALE_FORMAT) && locale != note.locale
      return release_note_save_error([ "Choose a valid translation locale other than the base locale." ])
    end
    saved = note.with_lock do
      authorize note, :update?
      translations = note.translations.dup
      text.strip.blank? ? translations.delete(locale) : translations[locale] = text
      note.update(translations: translations)
    end
    if saved
      respond_to do |format|
        format.turbo_stream { render json: note.slice(:status, :review_decision).merge(review_required: note.review_required?), content_type: "application/json" }
        format.html { redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id), notice: "Translation saved." }
      end
    else
      release_note_save_error(note.errors.full_messages)
    end
  end

  # DELETE /organizations/:organization_id/releases/:id/release_notes/:note_id
  def destroy_release_note
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :destroy?
    note.destroy
    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new"),
      notice: "Release note deleted."
  end

  # POST /organizations/:organization_id/releases/:id/release_notes/:note_id/apply
  # Copies the release note (plus every translation) onto each locale's StoreListing
  # `whats_new` field and flips the note to `applied`. No store push happens here —
  # that's a separate step ("Push to App Store / Google Play").
  def apply_release_note
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :apply?

    begin
      note.apply_to_store_listings!
      redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
        notice: "Applied to store listings. Push to #{note.ios? ? 'App Store' : 'Google Play'} when you're ready."
    rescue StandardError => e
      Rails.logger.error("apply_release_note failed: #{e.class}: #{e.message}")
      redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
        alert: "Couldn't apply: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  # POST /organizations/:organization_id/releases/:id/release_notes/:note_id/translate
  def translate_release_note
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :translate?

    @entitlements = @organization.entitlements
    unless @entitlements.ai_translations_remaining(@organization) > 0
      return redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
        alert: "You've reached your monthly AI translation limit."
    end

    if note.rendered_text.blank? || !note.listable.store_listings.where.not(locale: note.locale).exists?
      return release_note_save_error([ "Write release notes and add another listing locale before translating." ])
    end
    start_release_note_operation(note, "translation", ReleaseNoteTranslationJob)

    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
      status: :see_other, notice: "Translation started."
  rescue StandardError => e
    raise if e.is_a?(Pundit::NotAuthorizedError) || e.is_a?(ActiveRecord::RecordNotFound)
    release_note_save_error([ ErrorMessageSanitizer.sanitize(e) ])
  end

  # POST /organizations/:organization_id/releases/:id/release_notes/:note_id/rewrite
  def rewrite_release_note
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :rewrite?

    @entitlements = @organization.entitlements
    unless @entitlements.ai_rewrites_remaining(@organization) > 0
      return redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
        alert: "You've reached your monthly AI rewrite limit."
    end

    return release_note_save_error([ "Enter a changelog to rewrite." ]) if params[:raw_input].to_s.strip.blank?
    start_release_note_operation(note, "rewrite", ReleaseNoteRewriteJob, raw_input: params[:raw_input])

    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
      status: :see_other, notice: "AI rewrite started."
  rescue StandardError => e
    raise if e.is_a?(Pundit::NotAuthorizedError) || e.is_a?(ActiveRecord::RecordNotFound)
    release_note_save_error([ ErrorMessageSanitizer.sanitize(e) ])
  end

  # POST /organizations/:organization_id/releases/:id/release_notes/:note_id/fetch_commits
  def fetch_commits
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :rewrite?

    repo_url = params[:repo_url].to_s.strip
    from_ref = params[:from_ref].to_s.strip
    to_ref = params[:to_ref].to_s.strip

    if repo_url.blank? || from_ref.blank? || to_ref.blank?
      return render json: { error: "repo_url, from_ref, and to_ref are required" }, status: :unprocessable_content
    end

    begin
      commits = ReleaseNotes::GitLogFetcher.new(repo_url: repo_url, from_ref: from_ref, to_ref: to_ref).fetch!
      if commits.blank?
        render json: { commits: "", message: "No commits found between #{from_ref} and #{to_ref}" }
      else
        render json: { commits: commits }
      end
    rescue ReleaseNotes::GitLogFetcher::InvalidRepoUrlError => e
      render json: { error: e.message }, status: :unprocessable_content
    rescue ReleaseNotes::GitLogFetcher::FetchError => e
      render json: { error: e.message }, status: :bad_gateway
    end
  end

  # POST /organizations/:organization_id/releases/:id/release_notes/:note_id/submit_for_review
  def submit_for_review
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :submit_for_review?
    note.submit_for_review!(user: current_user)
    ReleaseNoteEvents::Notifier.notify_submitted_for_review(note, submitter: current_user)
    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
      notice: "Release note submitted for review. Admins have been notified."
  rescue RuntimeError, ActiveRecord::RecordInvalid => e
    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
      alert: "Could not submit: #{ErrorMessageSanitizer.sanitize(e)}"
  end

  # POST /organizations/:organization_id/releases/:id/release_notes/:note_id/approve_review
  def approve_review
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :approve_review?
    note.approve_review!(user: current_user, comment: params[:comment])
    ReleaseNoteEvents::Notifier.notify_approved(note, reviewer: current_user)
    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
      notice: "Release note approved."
  rescue RuntimeError, ActiveRecord::RecordInvalid => e
    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
      alert: "Could not approve: #{ErrorMessageSanitizer.sanitize(e)}"
  end

  # POST /organizations/:organization_id/releases/:id/release_notes/:note_id/reject_review
  def reject_review
    note = @organization.release_notes.for_app(@app).find(params[:note_id])
    authorize note, :reject_review?
    comment = params[:comment].to_s.strip
    note.reject_review!(user: current_user, comment: comment)
    ReleaseNoteEvents::Notifier.notify_changes_requested(note, reviewer: current_user, comment: comment)
    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
      notice: "Changes requested. The author has been notified."
  rescue RuntimeError, ActiveRecord::RecordInvalid => e
    redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: note.id),
      alert: "Could not request changes: #{ErrorMessageSanitizer.sanitize(e)}"
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  # Resolves the @app from the URL identifier ("apple_app_123" / "android_app_456").
  def resolve_release
    @app = find_release_app
    raise ActiveRecord::RecordNotFound, "App not found" unless @app
  end

  def find_release_app
    id = params[:id].to_s
    if id.start_with?("apple_app_")
      app_id = id.delete_prefix("apple_app_")
      @organization.apple_apps.find_by(id: app_id)
    elsif id.start_with?("android_app_")
      app_id = id.delete_prefix("android_app_")
      @organization.android_apps.find_by(id: app_id)
    end
  end

  def find_or_create_app_release
    selected_note = @organization.release_notes.for_app(@app).find(params[:note_id]) if params[:note_id].present?
    version_string = params[:version_string].presence || selected_note&.version_string.presence || latest_version_string_for(@app) ||
      @organization.release_notes.for_app(@app).where.not(status: "archived").order(created_at: :desc).pick(:version_string).presence || "unversioned"

    AppRelease.find_or_create_by!(
      organization: @organization,
      listable_type: @app.class.name,
      listable_id: @app.id,
      version_string: version_string
    )
  rescue ActiveRecord::RecordNotUnique
    AppRelease.find_by!(
      organization: @organization,
      listable_type: @app.class.name,
      listable_id: @app.id,
      version_string: version_string
    )
  end

  def latest_version_string_for(app)
    case app
    when AppleApp
      app.app_store_versions.order(created_at: :desc).first&.version_string
    when AndroidApp
      app.play_store_releases.order(created_at: :desc).first&.version_code
    end
  end

  def primary_locale_for(app)
    app&.primary_locale || "en-US"
  end

  def default_tab
    return "whats_new" if @app_release.primary_release_note.present?
    "listing"
  end

  def current_release_note
    if params[:note_id].present?
      @organization.release_notes.find_by(id: params[:note_id], listable_type: @app.class.name, listable_id: @app.id)
    else
      @app_release.primary_release_note
    end
  end

  def ensure_checklist!
    @organization.release_checklists.create_or_find_by!(listable: @app, version_string: @app_release.version_string) do |checklist|
      checklist.platform = @app_release.platform.to_s
      checklist.items = ReleaseChecklist::DEFAULT_ITEMS.deep_dup
    end
  end

  def validate_listing_locale(locale)
    message = if locale.blank?
      "Please select a locale."
    elsif !StoreListing.supported_locales(@app.class.name).include?(locale)
      "This locale is not supported by this store."
    end
    return true unless message

    redirect_to organization_release_path(@organization, params[:id], tab: "listing"), alert: message
    false
  end

  def store_listing_params
    params.require(:store_listing).permit(
      :app_name, :subtitle, :keywords, :short_description,
      :description, :promotional_text,
      :support_url, :marketing_url, :privacy_policy_url
    )
    # NOTE: whats_new is intentionally excluded — it's edited via the What's New tab.
  end

  def release_note_params
    params.require(:release_note).permit(
      :version_string, :build_number, :locale, :rendered_text, :raw_input
    ).tap do |permitted|
      if params[:release_note][:template_data].present?
        permitted[:template_data] = JSON.parse(params[:release_note][:template_data])
      end
    end
  end

  def start_release_note_operation(note, kind, job, **arguments)
    operation = ReleaseNotes::OperationStatus.new(note)
    id = operation.start!(kind)
    return unless id
    job.perform_later(organization_id: @organization.id, release_note_id: note.id, operation_id: id, **arguments)
  rescue StandardError => e
    operation.finish!(id, error: e) if id
    raise
  end

  def release_note_save_error(errors)
    respond_to do |format|
      format.turbo_stream { render json: { errors: errors }, content_type: "application/json", status: :unprocessable_content }
      format.html { redirect_to organization_release_path(@organization, params[:id], tab: "whats_new", note_id: params[:note_id]), alert: errors.to_sentence }
    end
  end

  def permitted_translation_fields
    raw = params[:fields]
    return "all" if raw.blank? || raw == "all"
    return "all" unless raw.is_a?(String)
    validated = raw.split(",").map(&:strip).select { |f| ALLOWED_TRANSLATION_FIELDS.include?(f) }
    validated.any? ? validated.join(",") : "all"
  end

  # Blocks push/submit actions when any required auto-detected checklist item
  # has severity "error". Called as `return if blocking_checklist_issues_redirect!(...)`.
  # Returns true (and performs the redirect) if there are blockers; returns false otherwise.
  def blocking_checklist_issues_redirect!(action_verb:)
    checklist = find_or_create_app_release.checklist
    return false unless checklist

    blocking = Array(checklist.auto_detected_items).select do |i|
      i["required"] == true && i["severity"] == "error"
    end
    return false if blocking.empty?

    message = "Cannot #{action_verb}: #{blocking.size} required issue(s) must be resolved. See the Checklist tab."
    respond_to do |format|
      format.html { redirect_to organization_release_path(@organization, params[:id], tab: "checklist"), alert: message }
      format.json { render json: { error: message }, status: :unprocessable_content }
    end
    true
  end

  def handle_push_upgrade_required
    payload = plan_upgrade_prompt_payload(
      current_plan: @organization.plan_tier,
      required_plan: Pricing::Entitlements.required_plan_for(:store_listing_push),
      feature: "store listing push",
      message: "Pushing metadata to the store requires a Pro plan or higher.",
      suggestion: "Upgrade to Pro to push store listing changes directly to App Store Connect and Google Play."
    )
    store_upgrade_prompt!(payload)
    respond_to do |format|
      format.html { redirect_to organization_release_path(@organization, params[:id]) }
      format.json { render json: { error: "Pushing metadata to the store requires a Pro plan or higher." }, status: :forbidden }
    end
  end

  def push_error_response(message, tab: nil)
    respond_to do |format|
      format.html { redirect_to organization_release_path(@organization, params[:id], tab: tab), alert: message }
      format.json { render json: { error: message }, status: :unprocessable_content }
    end
  end
end
