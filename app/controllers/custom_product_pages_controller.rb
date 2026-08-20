class CustomProductPagesController < ApplicationController
  include SanitizesApiErrors

  before_action :authenticate_user!
  before_action :set_org
  before_action :authorize_org_access!
  before_action :require_cpp_entitlement!, except: [ :index ]
  after_action :verify_authorized

  # GET /organizations/:organization_id/custom_product_pages
  def index
    authorize @organization, :show?
    set_current_organization!(@organization)

    @entitlements = @organization.entitlements
    @apple_apps = @organization.apple_apps.includes(:custom_product_pages).order(:name)
    @cpps_by_app = @organization.custom_product_pages.includes(:apple_app, :custom_product_page_versions).ordered.group_by(&:apple_app)
  end

  # GET /organizations/:organization_id/custom_product_pages/:id
  def show
    authorize @organization, :show?

    @entitlements = @organization.entitlements
    @cpp = @organization.custom_product_pages
                        .includes(custom_product_page_versions: :custom_product_page_localizations)
                        .find(params[:id])
    @app = @cpp.apple_app
    @tab = (params[:tab].presence || "overview").to_s

    case @tab
    when "keywords"
      load_keywords_data
    when "screenshots"
      @screenshot_projects = @organization.screenshot_projects.where(platform: [ "ios", "both" ]).order(:name)
      @has_asc_credentials = @organization.app_store_connect_credentials.where(active: true).exists?
      @localizations = @cpp.custom_product_page_localizations
    end
  end

  # GET /organizations/:organization_id/custom_product_pages/new
  def new
    authorize @organization, :show?

    @entitlements = @organization.entitlements
    @apple_apps = @organization.apple_apps.order(:name)
    @cpp = CustomProductPage.new
  end

  # POST /organizations/:organization_id/custom_product_pages
  def create
    authorize @organization, :manage_resources?

    @entitlements = @organization.entitlements
    app = @organization.apple_apps.find(params[:apple_app_id])

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_custom_product_pages_path(@organization),
        alert: "No active App Store Connect credential found."
    end

    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::CustomProductPages.new(client)

    # Use the app's primary locale, or the user-specified locale
    locale = params[:locale].presence || app.primary_locale || "en-US"

    # Optionally copy screenshots from the latest live version
    latest_version = app.app_store_versions&.find_by(app_store_state: "READY_FOR_SALE")
    version_template_id = latest_version&.version_id

    response = service.create(
      app_id: app.app_store_id,
      name: params[:name].to_s.strip,
      locale: locale,
      app_store_version_id: version_template_id,
      promotional_text: params[:promotional_text].presence
    )

    cpp_data = response["data"]
    attrs = cpp_data["attributes"] || {}

    @organization.custom_product_pages.create!(
      apple_app: app,
      remote_id: cpp_data["id"],
      name: attrs["name"] || params[:name].to_s.strip,
      visible: attrs["visible"] != false,
      raw_json: cpp_data
    )

    # Sync to pull versions/localizations
    CppSyncJob.perform_later(organization_id: @organization.id)

    redirect_to organization_custom_product_pages_path(@organization),
      notice: "Custom Product Page '#{params[:name]}' created successfully."
  rescue StandardError => e
    redirect_to new_organization_custom_product_page_path(@organization),
      alert: "Failed to create Custom Product Page: #{safe_error_message(e)}"
  end

  # PATCH /organizations/:organization_id/custom_product_pages/:id
  def update
    authorize @organization, :manage_resources?

    @cpp = @organization.custom_product_pages.find(params[:id])

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_custom_product_page_path(@organization, @cpp),
        alert: "No active App Store Connect credential found."
    end

    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::CustomProductPages.new(client)

    name = params[:name].to_s.strip.presence
    visible = params[:visible] != "0"

    service.update(cpp_id: @cpp.remote_id, name: name, visible: visible)
    @cpp.update!(name: name || @cpp.name, visible: visible)

    redirect_to organization_custom_product_page_path(@organization, @cpp),
      notice: "Custom Product Page updated."
  rescue StandardError => e
    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "overview"),
      alert: "Failed to update: #{safe_error_message(e)}"
  end

  # DELETE /organizations/:organization_id/custom_product_pages/:id
  def destroy
    authorize @organization, :manage_resources?

    @cpp = @organization.custom_product_pages.find(params[:id])

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_custom_product_pages_path(@organization),
        alert: "No active App Store Connect credential found."
    end

    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::CustomProductPages.new(client)

    service.delete(cpp_id: @cpp.remote_id)
    @cpp.destroy!

    redirect_to organization_custom_product_pages_path(@organization),
      notice: "Custom Product Page deleted."
  rescue StandardError => e
    redirect_to organization_custom_product_pages_path(@organization),
      alert: "Failed to delete: #{safe_error_message(e)}"
  end

  # GET /organizations/:organization_id/custom_product_pages/:id/fetch_screenshots
  def fetch_screenshots
    authorize @organization, :show?
    @cpp = @organization.custom_product_pages.find(params[:id])

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return render json: { error: "No active credentials" }, status: :unprocessable_content
    end

    client = AppStoreConnect::Client.new(credential: credential)
    screenshots_service = AppStoreConnect::Screenshots.new(client)
    cpp_service = AppStoreConnect::CustomProductPages.new(client)

    locale = params[:locale].presence || @cpp.custom_product_page_localizations.first&.locale || "en-US"

    cpp_localization = @cpp.custom_product_page_localizations.find_by(locale: locale)
    app = @cpp.apple_app

    # Fetch CPP and default screenshots IN PARALLEL (independent I/O calls).
    # Wrap each thread in with_connection to avoid leaking AR connections.
    cpp_screenshots = nil
    default_screenshots = nil

    threads = [
      Thread.new {
        ActiveRecord::Base.connection_pool.with_connection do
          cpp_screenshots = fetch_screenshots_for_localization(cpp_service, screenshots_service, cpp_localization, :cpp)
        end
      },
      Thread.new {
        ActiveRecord::Base.connection_pool.with_connection do
          default_screenshots = fetch_default_version_screenshots(app, locale, client, screenshots_service)
        end
      }
    ]
    threads.each { |t| t.join rescue Rails.logger.warn("CPP screenshot thread failed: #{$!.message}") }

    render json: {
      data: {
        locale: locale,
        cpp_screenshots: cpp_screenshots || [],
        default_screenshots: default_screenshots || [],
        display_types: AppStoreConnect::Screenshots::DISPLAY_TYPES.values.uniq
      }
    }
  rescue StandardError => e
    Rails.logger.error("CPP fetch_screenshots failed: #{e.class} - #{e.message}")
    render json: { error: safe_error_message(e) }, status: :internal_server_error
  end

  # POST /organizations/:organization_id/custom_product_pages/:id/upload_screenshots
  def upload_screenshots
    authorize @organization, :manage_resources?
    @cpp = @organization.custom_product_pages.find(params[:id])

    project = @organization.screenshot_projects.find(params[:screenshot_project_id] || params[:project_id])

    # JS sends either cpp_localization_id (remote_id) or locale string
    cpp_localization = if params[:cpp_localization_id].present?
      @cpp.custom_product_page_localizations.find_by!(remote_id: params[:cpp_localization_id])
    elsif params[:locale].present?
      @cpp.custom_product_page_localizations.find_by!(locale: params[:locale])
    else
      @cpp.custom_product_page_localizations.first!
    end

    presets = Array(params[:presets])

    # Check which presets have exported files available
    missing_presets = check_missing_preset_exports(project, presets)
    if missing_presets.any?
      preset_labels = { "ios_required" => "iPhone Required", "ios_optional" => "iPhone 5.5\"", "ios_ipad" => "iPad" }
      missing_labels = missing_presets.map { |p| preset_labels[p] || p }.join(", ")
      return render json: {
        error: "No exported screenshots found for: #{missing_labels}. Open the Screenshot Studio editor and use the Upload button to render and upload those sizes first."
      }, status: :unprocessable_content
    end

    config = {
      "cpp_localization_id" => cpp_localization.remote_id,
      "presets" => presets,
      "replace_existing" => params[:replace_existing] == "true" || params[:replace_existing] == true
    }

    upload = ScreenshotUpload.create!(
      screenshot_project: project,
      organization: @organization,
      target: "custom_product_page",
      config: config,
      status: "pending"
    )

    ScreenshotUploadJob.perform_later(upload.id)

    render json: { data: { id: upload.id, status: "pending" } }, status: :created
  rescue StandardError => e
    Rails.logger.error("CPP upload_screenshots failed: #{e.class} - #{e.message}")
    render json: { error: safe_error_message(e) }, status: :unprocessable_content
  end

  # GET /organizations/:organization_id/custom_product_pages/:id/upload_status
  def upload_status
    authorize @organization, :show?
    upload = @organization.screenshot_uploads.find(params[:upload_id])
    render json: { data: { id: upload.id, status: upload.status, progress: upload.progress } }
  end

  # POST /organizations/:organization_id/custom_product_pages/:id/sync
  def sync
    authorize @organization, :manage_resources?

    CppSyncJob.perform_later(organization_id: @organization.id)

    redirect_to organization_custom_product_pages_path(@organization),
      notice: "CPP sync started. Data will update shortly."
  end

  # PATCH /organizations/:organization_id/custom_product_pages/:id/update_localization
  def update_localization
    authorize @organization, :manage_resources?
    @cpp = @organization.custom_product_pages.find(params[:id])

    localization = @cpp.custom_product_page_localizations.find_by!(locale: params[:locale])

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "overview"),
        alert: "No active App Store Connect credential found."
    end

    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::CustomProductPages.new(client)

    promotional_text = params[:promotional_text].to_s.strip
    service.update_localization(localization_id: localization.remote_id, promotional_text: promotional_text)
    localization.update!(promotional_text: promotional_text)

    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "overview"),
      notice: "Promotional text updated for #{params[:locale]}."
  rescue StandardError => e
    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "overview"),
      alert: "Failed to update promotional text: #{safe_error_message(e)}"
  end

  # PATCH /organizations/:organization_id/custom_product_pages/:id/update_version
  def update_version
    authorize @organization, :manage_resources?
    @cpp = @organization.custom_product_pages.find(params[:id])

    version = @cpp.custom_product_page_versions.find(params[:version_id])

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "overview"),
        alert: "No active App Store Connect credential found."
    end

    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::CustomProductPages.new(client)

    deep_link = params[:deep_link].to_s.strip.presence
    service.update_version(version_id: version.remote_id, deep_link: deep_link)
    version.update!(deep_link: deep_link)

    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "overview"),
      notice: "Deep link updated."
  rescue StandardError => e
    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "overview"),
      alert: "Failed to update deep link: #{safe_error_message(e)}"
  end

  # POST /organizations/:organization_id/custom_product_pages/:id/add_keyword
  def add_keyword
    authorize @organization, :manage_resources?

    @cpp = @organization.custom_product_pages.find(params[:id])
    keyword_id = params[:keyword_id].to_s.strip

    if keyword_id.blank?
      return redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "keywords"),
        alert: "Please select a keyword to assign."
    end

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "keywords"),
        alert: "No active App Store Connect credential found."
    end

    # Keywords are linked at the localization level
    localization = resolve_cpp_localization(params[:locale])
    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::CustomProductPages.new(client)

    service.add_keywords(localization_id: localization.remote_id, keyword_ids: [ keyword_id ])

    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "keywords"),
      notice: "Keyword assigned to this Custom Product Page."
  rescue StandardError => e
    message = if e.message.include?("no released appStoreVersionLocalization")
      "Your app needs at least one live (approved) version on the App Store before you can assign keywords to a CPP. The current version appears to be rejected or not yet released."
    else
      "Failed to add keyword: #{safe_error_message(e)}"
    end
    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "keywords"),
      alert: message
  end

  # POST /organizations/:organization_id/custom_product_pages/:id/submit_for_review
  def submit_for_review
    authorize @organization, :manage_resources?

    @cpp = @organization.custom_product_pages.find(params[:id])
    draft_version = @cpp.draft_version

    unless draft_version
      return redirect_to organization_custom_product_page_path(@organization, @cpp),
        alert: "No draft version found to submit."
    end

    unless draft_version.submittable?
      return redirect_to organization_custom_product_page_path(@organization, @cpp),
        alert: "This version cannot be submitted. It may already be submitted or not in the correct state."
    end

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_custom_product_page_path(@organization, @cpp),
        alert: "No active App Store Connect credential found."
    end

    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::CustomProductPages.new(client)

    service.submit_for_review(
      app_id: @cpp.apple_app.app_store_id,
      cpp_version_id: draft_version.remote_id
    )

    draft_version.update!(submission_status: "submitted", submission_error: nil)

    redirect_to organization_custom_product_page_path(@organization, @cpp),
      notice: "Custom Product Page submitted for App Review."
  rescue StandardError => e
    message = humanize_submission_error(e.message)
    # Sanitize before persisting — the raw message may contain API credentials
    draft_version&.update(submission_status: "failed", submission_error: safe_error_message(message))

    redirect_to organization_custom_product_page_path(@organization, @cpp),
      alert: "Failed to submit for review: #{message}"
  end

  # DELETE /organizations/:organization_id/custom_product_pages/:id/remove_keyword
  def remove_keyword
    authorize @organization, :manage_resources?

    @cpp = @organization.custom_product_pages.find(params[:id])
    keyword_id = params[:keyword_id].to_s.strip

    if keyword_id.blank?
      return redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "keywords"),
        alert: "Keyword ID is required."
    end

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    unless credential
      return redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "keywords"),
        alert: "No active App Store Connect credential found."
    end

    localization = resolve_cpp_localization(params[:locale])
    client = AppStoreConnect::Client.new(credential: credential)
    service = AppStoreConnect::CustomProductPages.new(client)

    service.remove_keywords(localization_id: localization.remote_id, keyword_ids: [ keyword_id ])

    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "keywords"),
      notice: "Keyword removed from CPP."
  rescue StandardError => e
    redirect_to organization_custom_product_page_path(@organization, @cpp, tab: "keywords"),
      alert: "Failed to remove keyword: #{safe_error_message(e)}"
  end

  private

  def set_org
    # Scoped to memberships so non-member and non-existent ids both 404.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def authorize_org_access!
    authorize @organization, :show?
  end

  def require_cpp_entitlement!
    return if @organization.entitlements.custom_product_pages_enabled?

    redirect_to organization_custom_product_pages_path(@organization),
      alert: "Custom Product Pages requires a Pro plan or higher."
  end

  def load_keywords_data
    @assigned_keywords = []
    @available_keywords = []
    @localizations = @cpp.custom_product_page_localizations

    localization = @localizations.first

    # Pull available keywords from the local StoreListing (already synced from Apple)
    # — no extra API call needed, and it always has the latest synced keywords
    primary_listing = @cpp.apple_app.store_listings.find_by(locale: localization&.locale) ||
                      @cpp.apple_app.store_listings.first
    if primary_listing&.keywords.present?
      @available_keywords = primary_listing.keywords.split(",").map(&:strip).reject(&:blank?)
    end

    # Fetch assigned keywords from Apple (this requires an API call)
    return unless localization

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    return unless credential

    begin
      client = AppStoreConnect::Client.new(credential: credential)
      service = AppStoreConnect::CustomProductPages.new(client)
      @assigned_keywords = service.keywords(localization_id: localization.remote_id)
    rescue StandardError => e
      Rails.logger.warn("CPP keywords fetch failed: #{e.message}")
    end
  end

  def resolve_cpp_localization(locale)
    loc = if locale.present?
      @cpp.custom_product_page_localizations.find_by!(locale: locale)
    else
      @cpp.custom_product_page_localizations.first!
    end
    loc
  end

  def fetch_screenshots_for_localization(cpp_service, screenshots_service, localization, type)
    return [] unless localization

    sets = if type == :cpp
      response = cpp_service.screenshot_sets(localization_id: localization.remote_id)
      response["data"] || []
    else
      screenshots_service.list_screenshot_sets(localization_id: localization)
    end

    # Fetch screenshots for all sets IN PARALLEL (each is an independent API call)
    fetch_screenshots_for_sets_parallel(sets, screenshots_service)
  rescue StandardError => e
    Rails.logger.warn("fetch_screenshots_for_localization failed: #{e.message}")
    []
  end

  def fetch_default_version_screenshots(app, locale, client, screenshots_service)
    versions_service = AppStoreConnect::Versions.new(client)

    live_version = app.app_store_versions&.find_by(app_store_state: "READY_FOR_SALE")
    version = live_version || app.app_store_versions&.order(created_at: :desc)&.first
    return [] unless version

    localizations = versions_service.localizations(version_id: version.version_id)
    loc_data = localizations.is_a?(Array) ? localizations : (localizations["data"] || [])

    matching_loc = loc_data.find { |l| l.dig("attributes", "locale") == locale }
    return [] unless matching_loc

    sets = screenshots_service.list_screenshot_sets(localization_id: matching_loc["id"])
    fetch_screenshots_for_sets_parallel(sets, screenshots_service)
  rescue StandardError => e
    Rails.logger.warn("fetch_default_version_screenshots failed: #{e.message}")
    []
  end

  # Checks which presets have no exported files on disk
  def check_missing_preset_exports(project, presets)
    exports_dir = project.exports_directory
    existing_resolutions = if exports_dir.exist?
      exports_dir.children.select(&:directory?).map { |d| d.basename.to_s }
    else
      []
    end

    presets.select do |preset_key|
      preset_sizes = ScreenshotProject::EXPORT_PRESETS[preset_key] || []
      preset_resolutions = preset_sizes.map { |p| "#{p[:width]}x#{p[:height]}" }
      (preset_resolutions & existing_resolutions).empty?
    end
  end

  def humanize_submission_error(message)
    case message
    when /no released appStoreVersionLocalization/i
      "Your app needs at least one approved and released version on the App Store before you can submit a Custom Product Page for review."
    when /must have an approved appStoreVersions/i, /approved appStoreVersions for platform/i
      "Your app needs at least one approved version live on the App Store before you can submit a CPP separately. Get your app approved first, then submit the CPP."
    when /already has a review submission/i, /CONFLICT/i
      "A review submission is already in progress for this app. Wait for it to complete before submitting again."
    when /not in a state that allows submission/i, /not in valid state/i, /cannot be reviewed/i
      "This Custom Product Page is not ready for review. Make sure you have: (1) uploaded screenshots for all required device sizes, (2) your app has a live version on the App Store. Check App Store Connect for specific validation errors."
    else
      safe_error_message(message)
    end
  end

  # Fetches screenshots for multiple sets concurrently using threads.
  # Each thread makes one API call — threads are I/O-bound (waiting on Apple),
  # so this uses negligible CPU/memory on the Hetzner CX22.
  # Wrapped in with_connection to avoid leaking AR connections from the pool.
  def fetch_screenshots_for_sets_parallel(sets, screenshots_service)
    return [] if sets.empty?

    results = Array.new(sets.size)

    threads = sets.each_with_index.map do |set, i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          display_type = set.dig("attributes", "screenshotDisplayType")
          screenshots = screenshots_service.list_screenshots(set_id: set["id"])
          next if screenshots.empty?

          results[i] = {
            display_type: display_type,
            set_id: set["id"],
            screenshots: screenshots.map { |s|
              attrs = s["attributes"] || {}
              asset = attrs["imageAsset"] || {}
              { id: s["id"], file_name: attrs["fileName"], width: asset["width"], height: asset["height"], url: asset["templateUrl"] }
            }
          }
        end
      end
    end
    threads.each { |t| t.join rescue Rails.logger.warn("CPP screenshot set thread failed: #{$!.message}") }

    results.compact
  end
end
