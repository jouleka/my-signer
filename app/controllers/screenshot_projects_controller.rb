class ScreenshotProjectsController < ApplicationController
  MAX_EXPORT_FILES_PER_BATCH = 60

  before_action :authenticate_user!
  before_action :set_org
  before_action :set_project, only: [ :show, :edit, :update, :destroy, :editor, :apply_template, :upload_export, :start_store_upload, :upload_status, :current_store_screenshots, :background_image_file, :custom_sticker_image, :upload_background_image, :remove_background_image, :upload_custom_sticker_image, :delete_custom_sticker_image ]
  before_action :redirect_if_project_plan_frozen!, only: [ :show, :edit, :editor ]
  before_action :ensure_project_plan_access!, only: [ :update, :apply_template, :upload_export, :start_store_upload, :upload_background_image, :upload_custom_sticker_image ]

  def index
    authorize @organization, :show?
    @projects = @organization.screenshot_projects.order(updated_at: :desc)
    @plan_frozen_project_ids = ScreenshotProject.plan_frozen_ids_for(@organization)
  end

  def new
    authorize @organization, :manage_resources?
    @project = @organization.screenshot_projects.new(platform: "both")
    set_project_create_gate_state(@project)
  end

  def create
    authorize @organization, :manage_resources?
    @project = @organization.screenshot_projects.new(project_params)

    template_key = @project.template
    if template_key.present? && ScreenshotProject::TEMPLATES.key?(template_key)
      @project.settings = ScreenshotProject.template_settings(template_key)
    else
      @project.template = nil
      @project.settings = ScreenshotProject::DEFAULT_CUSTOM_SETTINGS.merge(@project.settings || {})
    end
    @project.settings = normalize_caption_layout_settings(@project.settings)

    created = false
    @organization.with_lock do
      created = @project.save
    end

    if created
      redirect_to editor_organization_screenshot_project_path(@organization, @project), notice: "Project created successfully"
    else
      return if render_quota_exhausted_json_for(@project)

      attach_quota_upgrade_guidance!(@project)
      store_quota_upgrade_prompt!(@project, now: true)
      set_project_create_gate_state(@project)
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize @organization, :show?
    redirect_to editor_organization_screenshot_project_path(@organization, @project)
  end

  def edit
    authorize @organization, :manage_resources?
  end

  def update
    authorize @organization, :manage_resources?

    attrs = project_params.to_h
    scene_template_defaults = nil

    if attrs.key?("template")
      template_key = attrs["template"]
      if template_key.present? && ScreenshotProject::TEMPLATES.key?(template_key)
        attrs["settings"] = ScreenshotProject.template_settings(template_key)
        if !request.format.json? && template_key != @project.template
          scene_template_defaults = build_scene_template_defaults(template_key)
        end
      else
        attrs["template"] = nil
        attrs["settings"] = (@project.settings || {}).merge(attrs["settings"] || {})
      end
    elsif attrs["settings"].present? && @project.settings.present?
      attrs["settings"] = @project.settings.merge(attrs["settings"])
    end
    attrs["settings"] = normalize_caption_layout_settings(attrs["settings"]) if attrs["settings"].present?

    project_updated = false
    ActiveRecord::Base.transaction do
      project_updated = @project.update(attrs)
      raise ActiveRecord::Rollback unless project_updated

      if scene_template_defaults.present?
        apply_template_defaults_to_all_scenes!(scene_template_defaults)
      end
    end

    if project_updated
      respond_to do |format|
        format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project), notice: "Project updated successfully" }
        format.json { render json: { status: "ok" } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: { errors: @project.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def destroy
    authorize @organization, :manage_resources?
    @project.destroy
    redirect_to organization_screenshot_projects_path(@organization), notice: "Project deleted"
  end

  def editor
    authorize @organization, :show?
    response.set_header("Cache-Control", "private, max-age=0, must-revalidate")
    @plan_payload = Pricing::PlanPayload.for_organization(@organization)
    @project_plan_access_state = @project.plan_access_state
    @project_plan_frozen_reason = @project.plan_frozen_reason
    @scenes = @project.screenshot_scenes.order(:position)
    @brand_settings = @organization.brand_settings || {}
    @apple_apps = @organization.apple_apps.order(:name)
    @android_apps = @organization.android_apps.order(:name)
    @has_other_projects = @organization.screenshot_projects.where.not(id: @project.id).exists?
    @has_asc_credentials = @organization.app_store_connect_credentials.where(active: true).exists?
    @has_gp_credentials = @organization.google_play_credentials.where(active: true).exists?
    @editable_versions = @organization.app_store_versions.editable.includes(:apple_app).order(created_at: :desc)
    @custom_product_pages = @organization.custom_product_pages
      .includes(:apple_app, custom_product_page_versions: :custom_product_page_localizations)
      .order(:name)
  end

  def apply_template
    authorize @organization, :manage_resources?
    template_key = params[:template_key]

    unless ScreenshotProject::TEMPLATES.key?(template_key)
      render json: { error: "Invalid template" }, status: :unprocessable_content
      return
    end

    template_settings = ScreenshotProject.template_settings(template_key)
    @project.template = template_key
    @project.settings = normalize_caption_layout_settings((@project.settings || {}).merge(template_settings))

    if @project.save
      render json: { status: "ok", settings: @project.settings }
    else
      render json: { errors: @project.errors.full_messages }, status: :unprocessable_content
    end
  end

  # POST /organizations/:organization_id/screenshot_projects/:id/upload_export
  # Receives a batch of rendered PNGs from the browser and writes them to disk
  # Supports both multipart FormData (binary files) and legacy JSON (base64)
  def upload_export
    authorize @organization, :manage_resources?

    unless @organization.store_upload_enabled?
      return render_plan_upgrade_required_json(
        required_plan: Pricing::Entitlements.required_plan_for(:store_uploads),
        message: "Store uploads are available on paid plans only",
        feature: "direct store uploads"
      )
    end

    # Rate limit: 1 batch per 10 seconds per user
    cache_key = "screenshot_upload:#{current_user.id}"
    if Rails.cache.read(cache_key)
      return render json: { message: "Please wait before uploading again" }, status: :too_many_requests
    end
    Rails.cache.write(cache_key, true, expires_in: 10.seconds)

    screenshots = params[:screenshots]
    # Multipart FormData with screenshots[0][file], screenshots[1][file] etc.
    # is parsed by Rack as a Hash with string keys ("0", "1"), not an Array.
    screenshots = screenshots.values if screenshots.is_a?(ActionController::Parameters) || screenshots.is_a?(Hash)
    unless screenshots.is_a?(Array) && screenshots.any?
      return render json: { message: "Screenshots array is required" }, status: :unprocessable_content
    end

    if screenshots.size > MAX_EXPORT_FILES_PER_BATCH
      return render json: { message: "Too many screenshots (max #{MAX_EXPORT_FILES_PER_BATCH})" }, status: :unprocessable_content
    end

    # Phase 1: Pre-decode and validate all images, summing total bytes
    decoded = []
    total_bytes = 0
    max_encoded_image_data_size = 14.megabytes
    scene_positions = @project.screenshot_scenes.pluck(:position)
    if scene_positions.empty?
      return render json: { message: "Add at least one scene before exporting" }, status: :unprocessable_content
    end

    seen_files = {}

    screenshots.each do |screenshot|
      width = screenshot[:width].to_i
      height = screenshot[:height].to_i
      position = screenshot[:scene_position].to_i

      next if width <= 0 || width > 4096 || height <= 0 || height > 4096
      next unless scene_positions.include?(position)
      next if seen_files["#{width}x#{height}:#{position}"]
      seen_files["#{width}x#{height}:#{position}"] = true

      # Support both multipart file upload and legacy base64
      raw = nil
      if screenshot[:file].respond_to?(:read)
        next if screenshot[:file].respond_to?(:size) && screenshot[:file].size.to_i > 10.megabytes

        raw = screenshot[:file].read
        screenshot[:file].rewind
      elsif screenshot[:image_data].present?
        encoded = screenshot[:image_data].to_s.sub(%r{^data:image/png;base64,}, "")
        next if encoded.bytesize > max_encoded_image_data_size

        begin
          raw = Base64.decode64(encoded)
        rescue ArgumentError
          next
        end
      else
        next
      end

      # Validate PNG magic bytes
      next unless raw.byteslice(0, 4) == "\x89PNG".b

      # Validate file size (max 10MB per screenshot)
      next if raw.bytesize > 10.megabytes

      total_bytes += raw.bytesize
      decoded << { width: width, height: height, position: position, raw: raw }
    end

    if decoded.empty?
      return render json: { message: "No valid screenshots found in request" }, status: :unprocessable_content
    end

    conflict_error = nil
    quota_error = nil
    results = []

    @organization.with_lock do
      @project.lock!

      if ScreenshotUpload.active_for_project?(organization_id: @organization.id, screenshot_project_id: @project.id)
        conflict_error = "A store upload is already in progress for this project. Please wait until it completes."
        next
      end

      # This endpoint is used for store uploads, so replace prior export batch to avoid stale-file buildup.
      current_project_export_bytes = @project.export_storage_bytes
      required_delta = [ total_bytes - current_project_export_bytes, 0 ].max
      unless @project.org_within_export_quota?(required_delta, use_cache: false)
        limit_label = human_storage_limit(@project.max_export_storage_bytes_per_organization)
        quota_error = "Organization export storage quota exceeded (max #{limit_label})"
        next
      end

      @project.clear_exports_directory!

      # Phase 3: Write all validated files to disk and cloud storage
      decoded.each do |entry|
        resolution = "#{entry[:width]}x#{entry[:height]}"
        resolution_dir = @project.ensure_resolution_directory!(width: entry[:width], height: entry[:height])

        file_name = "screenshot_#{entry[:position].to_s.rjust(2, '0')}.png"
        File.binwrite(resolution_dir.join(file_name), entry[:raw])

        # Also store via ActiveStorage for cloud-compatible access
        ScreenshotExport.upsert_export!(
          project: @project,
          resolution: resolution,
          scene_position: entry[:position],
          locale: nil,
          image_data: entry[:raw]
        )

        results << { resolution: resolution, scene_position: entry[:position], file_size: entry[:raw].bytesize }
      end
    end

    return render json: { message: conflict_error }, status: :conflict if conflict_error
    if quota_error
      return render_quota_exhausted_json(
        message: quota_error,
        current_plan: @organization.plan_tier,
        next_plan: @organization.entitlements.next_plan_tier,
        feature: "export storage",
        suggestion: quota_upgrade_suggestion(
          current_plan: @organization.plan_tier,
          next_plan: @organization.entitlements.next_plan_tier,
          feature: "export storage"
        )
      )
    end

    ScreenshotProject.invalidate_export_quota_cache!(@organization.id)

    render json: { data: { uploaded: results.size, screenshots: results } }, status: :created
  end

  # POST /organizations/:organization_id/screenshot_projects/:id/start_store_upload
  # Creates a ScreenshotUpload record and enqueues the background job
  def start_store_upload
    authorize @organization, :manage_resources?

    unless @organization.store_upload_enabled?
      return render_plan_upgrade_required_json(
        required_plan: Pricing::Entitlements.required_plan_for(:store_uploads),
        message: "Store uploads are available on paid plans only",
        feature: "direct store uploads"
      )
    end

    # Rate limit: 1 upload trigger per 30 seconds per user
    cache_key = "screenshot_store_upload:#{current_user.id}"
    if Rails.cache.read(cache_key)
      return render json: { message: "Please wait before starting another upload" }, status: :too_many_requests
    end
    Rails.cache.write(cache_key, true, expires_in: 30.seconds)

    target = params[:target]
    config = params[:config]&.permit(:version_id, :locale, :package_name, :language, :replace_existing, :all_locales, :cpp_localization_id, presets: [], locales: [])&.to_h || {}

    unless ScreenshotUpload::TARGETS.include?(target)
      return render json: { message: "Invalid target. Must be one of: #{ScreenshotUpload::TARGETS.join(', ')}" }, status: :unprocessable_content
    end

    config, config_error = normalize_store_upload_config(project: @project, target: target, config: config)
    return render json: { message: config_error }, status: :unprocessable_content if config_error

    upload = nil
    conflict_error = nil
    daily_limit_error = nil
    daily_limit_suggestion = nil
    exports_error = nil

    @organization.with_lock do
      @project.lock!

      daily_limit = ScreenshotUpload.daily_limit_for(@organization)
      unless ScreenshotUpload.within_daily_limit?(@organization.id, limit: daily_limit)
        daily_limit_error = "Daily upload limit reached (max #{daily_limit} uploads per 24 hours)"
        daily_limit_suggestion = quota_upgrade_suggestion(
          current_plan: @organization.plan_tier,
          next_plan: @organization.entitlements.next_plan_tier,
          feature: "daily store uploads"
        )
        next
      end

      if ScreenshotUpload.active_for_project?(organization_id: @organization.id, screenshot_project_id: @project.id)
        conflict_error = "An upload is already in progress for this project"
        next
      end

      exports_dir = @project.exports_directory
      has_local_exports = exports_dir.exist? && exports_dir.glob("**/*.png").any?
      has_cloud_exports = @project.screenshot_exports.joins(:image_attachment).any?
      unless has_local_exports || has_cloud_exports
        exports_error = "No exported screenshots found. Render and upload exports first."
        next
      end

      upload = @organization.screenshot_uploads.new(
        screenshot_project: @project,
        target: target,
        config: config
      )
      upload.save
    end

    if daily_limit_error
      return render_quota_exhausted_json(
        message: daily_limit_error,
        current_plan: @organization.plan_tier,
        next_plan: @organization.entitlements.next_plan_tier,
        feature: "daily store uploads",
        suggestion: daily_limit_suggestion
      )
    end
    return render json: { message: conflict_error }, status: :conflict if conflict_error
    return render json: { message: exports_error }, status: :unprocessable_content if exports_error

    if upload&.persisted?
      ScreenshotUploadJob.perform_later(upload.id)
      render json: { data: { id: upload.id, status: upload.status } }, status: :created
    else
      render json: { message: upload&.errors&.full_messages&.join(", ") || "Failed to create upload" }, status: :unprocessable_content
    end
  end

  # GET /organizations/:organization_id/screenshot_projects/:id/upload_status
  # Returns the current status and progress of a store upload (for polling)
  def upload_status
    authorize @organization, :show?

    upload = @organization.screenshot_uploads.find(params[:upload_id])
    render json: {
      data: {
        id: upload.id,
        status: upload.status,
        progress: upload.progress
      }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { message: "Upload not found" }, status: :not_found
  end

  # GET /organizations/:organization_id/screenshot_projects/:id/current_store_screenshots
  # Fetches currently live screenshots from App Store Connect or Google Play
  def current_store_screenshots
    authorize @organization, :show?

    target = params[:target]
    unless %w[app_store_connect google_play].include?(target)
      return render json: { message: "Invalid target" }, status: :unprocessable_content
    end

    # Rate limit: 1 fetch per 15 seconds per user per target
    cache_key = "current_store_screenshots:#{current_user.id}:#{target}"
    if Rails.cache.read(cache_key)
      return render json: { message: "Please wait before fetching again" }, status: :too_many_requests
    end
    Rails.cache.write(cache_key, true, expires_in: 15.seconds)

    screenshots = {}

    begin
      if target == "app_store_connect"
        screenshots = fetch_asc_current_screenshots
      else
        screenshots = fetch_gp_current_screenshots
      end
    rescue => e
      Rails.logger.error("Failed to fetch current store screenshots: #{e.class} - #{e.message}")
      return render json: { message: "Failed to fetch screenshots: #{ErrorMessageSanitizer.sanitize(e)}" }, status: :unprocessable_content
    end

    render json: { data: screenshots }
  end

  # GET /organizations/:organization_id/screenshot_projects/:id/background_image_file
  # Stable project-scoped URL for background image previews and editor rendering.
  def background_image_file
    authorize @organization, :show?
    attachment = @project.background_image.attachment
    blob = attachment&.blob
    return head :not_found unless blob

    unless blob_available?(blob)
      Rails.logger.warn("Background image blob missing for project_id=#{@project.id}, blob_id=#{blob.id}")
      attachment.purge
      return head :not_found
    end

    redirect_to rails_storage_proxy_path(attachment, only_path: true)
  end

  # GET /organizations/:organization_id/screenshot_projects/:id/custom_sticker_images/:attachment_id
  # Stable project-scoped URL for custom sticker previews and editor rendering.
  def custom_sticker_image
    authorize @organization, :show?
    attachment = @project.custom_sticker_images.attachments.find_by(id: params[:attachment_id])
    blob = attachment&.blob
    return head :not_found unless blob

    unless blob_available?(blob)
      Rails.logger.warn("Custom sticker blob missing for project_id=#{@project.id}, attachment_id=#{attachment.id}, blob_id=#{blob.id}")
      attachment.purge
      return head :not_found
    end

    redirect_to rails_storage_proxy_path(attachment, only_path: true)
  end

  # POST /organizations/:organization_id/screenshot_projects/:id/upload_background_image
  def upload_background_image
    authorize @organization, :manage_resources?

    file = params[:file]
    unless file.present? && file.respond_to?(:content_type)
      return render json: { message: "File is required" }, status: :unprocessable_content
    end

    unless ScreenshotProject::ALLOWED_BG_IMAGE_TYPES.include?(file.content_type)
      return render json: { message: "File must be PNG, JPEG, or WebP" }, status: :unprocessable_content
    end

    if file.size > ScreenshotProject::MAX_BG_IMAGE_SIZE
      return render json: { message: "File must be less than 10 MB" }, status: :unprocessable_content
    end

    unless valid_image_magic_bytes?(file)
      return render json: { message: "File content does not match a valid image format" }, status: :unprocessable_content
    end

    upload_error = nil
    attached = false

    @organization.with_lock do
      @project.lock!

      existing_size = @project.background_image.attached? ? @project.background_image.blob.byte_size : 0
      required_delta = [ file.size - existing_size, 0 ].max
      unless @project.org_within_media_quota?(required_delta, use_cache: false)
        limit_label = human_storage_limit(@project.max_media_storage_bytes_per_organization)
        upload_error = "Organization screenshot media quota exceeded (max #{limit_label})"
        next
      end

      @project.background_image.attach(file)
      attached = @project.background_image.attached?
    end

    return render json: { message: upload_error }, status: :unprocessable_content if upload_error

    if attached
      ScreenshotProject.invalidate_media_quota_cache!(@organization.id)
      project_path = organization_screenshot_project_path(@organization, @project)
      render json: { url: "#{project_path}/background_image_file" }
    else
      render json: { message: "Failed to attach image" }, status: :unprocessable_content
    end
  end

  # DELETE /organizations/:organization_id/screenshot_projects/:id/remove_background_image
  def remove_background_image
    authorize @organization, :manage_resources?

    if @project.background_image.attached?
      @project.background_image.purge
      ScreenshotProject.invalidate_media_quota_cache!(@organization.id)
    end
    render json: { status: "ok" }
  end

  # POST /organizations/:organization_id/screenshot_projects/:id/upload_custom_sticker_image
  def upload_custom_sticker_image
    authorize @organization, :manage_resources?

    file = params[:file]
    unless file.present? && file.respond_to?(:content_type)
      return render json: { message: "File is required" }, status: :unprocessable_content
    end

    unless ScreenshotProject::ALLOWED_CUSTOM_STICKER_TYPES.include?(file.content_type)
      return render json: { message: "File must be PNG, JPEG, or WebP" }, status: :unprocessable_content
    end

    if file.size > ScreenshotProject::MAX_CUSTOM_STICKER_SIZE
      return render json: { message: "File must be less than 5 MB" }, status: :unprocessable_content
    end

    unless valid_image_magic_bytes?(file)
      return render json: { message: "File content does not match a valid image format" }, status: :unprocessable_content
    end

    upload_error = nil
    attachment = nil

    @organization.with_lock do
      @project.lock!

      unless @project.org_within_media_quota?(file.size, use_cache: false)
        limit_label = human_storage_limit(@project.max_media_storage_bytes_per_organization)
        upload_error = "Organization screenshot media quota exceeded (max #{limit_label})"
        next
      end

      if @project.custom_sticker_images.count >= ScreenshotProject::MAX_CUSTOM_STICKERS_PER_PROJECT
        upload_error = "Maximum of #{ScreenshotProject::MAX_CUSTOM_STICKERS_PER_PROJECT} custom sticker images per project"
        next
      end

      @project.custom_sticker_images.attach(file)
      attachment = @project.custom_sticker_images.last
    end

    return render json: { message: upload_error }, status: :unprocessable_content if upload_error

    if attachment&.blob
      ScreenshotProject.invalidate_media_quota_cache!(@organization.id)
      project_path = organization_screenshot_project_path(@organization, @project)
      render json: {
        id: attachment.blob.signed_id,
        attachment_id: attachment.id,
        url: "#{project_path}/custom_sticker_images/#{attachment.id}",
        filename: attachment.blob.filename.to_s
      }
    else
      render json: { message: "Failed to attach image" }, status: :unprocessable_content
    end
  end

  # DELETE /organizations/:organization_id/screenshot_projects/:id/delete_custom_sticker_image
  def delete_custom_sticker_image
    authorize @organization, :manage_resources?

    signed_id = params[:signed_id]
    attachment_id = params[:attachment_id]
    unless signed_id.present? || attachment_id.present?
      return render json: { message: "signed_id or attachment_id is required" }, status: :unprocessable_content
    end

    attachment = nil
    if attachment_id.present?
      attachment = @project.custom_sticker_images.attachments.find_by(id: attachment_id)
    end
    if attachment.nil? && signed_id.present?
      attachment = @project.custom_sticker_images.find { |a| a.blob.signed_id == signed_id }
      if attachment.nil? && signed_id.to_s.match?(/\A\d+\z/)
        attachment = @project.custom_sticker_images.attachments.find_by(id: signed_id)
      end
    end

    if attachment
      attachment.purge
      ScreenshotProject.invalidate_media_quota_cache!(@organization.id)
      render json: { status: "ok" }
    else
      render json: { message: "Image not found" }, status: :not_found
    end
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_project
    @project = @organization.screenshot_projects.find(params[:id])
  end

  # Fetch current screenshots from App Store Connect for the selected version/locale
  def fetch_asc_current_screenshots
    version_id = params[:version_id]
    locale = params[:locale].to_s.strip.presence || @project.default_locale.to_s

    return { screenshots: [], message: "No version selected" } if version_id.blank?

    credential = @organization.app_store_connect_credentials.find_by(active: true)
    return { screenshots: [], message: "No active App Store Connect credentials" } unless credential

    client = AppStoreConnect::Client.new(credential: credential)
    versions_service = AppStoreConnect::Versions.new(client)
    screenshots_service = AppStoreConnect::Screenshots.new(client)

    localizations = versions_service.localizations(version_id: version_id)
    localization = localizations.find { |loc| loc.dig("attributes", "locale") == locale }

    return { screenshots: [], message: "Localization '#{locale}' not found" } unless localization

    localization_id = localization["id"]
    screenshot_sets = screenshots_service.list_screenshot_sets(localization_id: localization_id)

    all_screenshots = []
    screenshot_sets.each do |set|
      display_type = set.dig("attributes", "screenshotDisplayType")
      screenshots = screenshots_service.list_screenshots(set_id: set["id"])
      screenshots.each do |ss|
        attrs = ss["attributes"] || {}
        image_url = attrs.dig("imageAsset", "templateUrl")
        # ASC templateUrl has {w}x{h} placeholders - replace with actual dimensions
        if image_url.present?
          width = attrs.dig("imageAsset", "width") || 300
          height = attrs.dig("imageAsset", "height") || 600
          # Build a thumbnail URL (capped at 230px wide for display)
          thumb_w = [ width, 230 ].min
          thumb_h = (thumb_w.to_f / width * height).round
          image_url = image_url.gsub("{w}", thumb_w.to_s).gsub("{h}", thumb_h.to_s).gsub("{f}", "png")
        end

        all_screenshots << {
          id: ss["id"],
          display_type: display_type,
          file_name: attrs["fileName"],
          file_size: attrs["fileSize"],
          width: attrs.dig("imageAsset", "width"),
          height: attrs.dig("imageAsset", "height"),
          url: image_url
        }
      end
    end

    { screenshots: all_screenshots }
  end

  # Fetch current screenshots from Google Play for the selected package/language
  def fetch_gp_current_screenshots
    package_name = params[:package_name]
    language = params[:language].to_s.strip.presence || @project.default_locale.to_s

    return { screenshots: [], message: "No package name provided" } if package_name.blank?

    credential = @organization.google_play_credentials.find_by(active: true)
    return { screenshots: [], message: "No active Google Play credentials" } unless credential

    client = GooglePlay::Client.new(credential: credential)
    screenshots_service = GooglePlay::Screenshots.new(client)

    results = screenshots_service.fetch_current_screenshots(
      package_name: package_name,
      language: language
    )

    all_screenshots = []
    results.each do |image_type, images|
      images.each do |img|
        all_screenshots << {
          id: img[:id],
          image_type: image_type,
          url: img[:url],
          sha256: img[:sha256]
        }
      end
    end

    { screenshots: all_screenshots }
  end

  def valid_image_magic_bytes?(file)
    header = file.read(12)
    file.rewind
    return false unless header

    png  = header.byteslice(0, 4) == "\x89PNG".b
    jpeg = header.byteslice(0, 3) == "\xFF\xD8\xFF".b
    webp = header.byteslice(0, 4) == "RIFF".b && header.byteslice(8, 4) == "WEBP".b

    png || jpeg || webp
  end

  def blob_available?(blob)
    return false unless blob
    blob.service.exist?(blob.key)
  rescue StandardError => e
    Rails.logger.warn("Blob existence check failed for blob_id=#{blob&.id}: #{e.class}: #{e.message}")
    true
  end

  TEMPLATE_SCENE_POSITION_KEYS = %w[text_position_x text_position_y text_rotation].freeze
  TEMPLATE_STICKER_KEYS = %w[id type emoji asset_key image_url x y size rotation color text].freeze
  TEMPLATE_MAX_STICKERS_PER_SCENE = 20

  def build_scene_template_defaults(template_key)
    template_settings = ScreenshotProject::TEMPLATES.dig(template_key, :settings) || {}
    overrides = {}

    TEMPLATE_SCENE_POSITION_KEYS.each do |key|
      overrides[key] = template_settings[key] if template_settings.key?(key)
    end

    # Stickers are scene-only data, so copy template defaults into each scene.
    overrides["stickers"] = normalize_template_stickers(template_settings["default_stickers"])

    {
      caption_text: template_settings["caption_text"].to_s,
      subtitle_text: template_settings["subtitle_text"].to_s,
      overrides: overrides
    }
  end

  def normalize_template_stickers(stickers)
    Array(stickers).first(TEMPLATE_MAX_STICKERS_PER_SCENE).filter_map.with_index do |sticker, idx|
      next unless sticker.is_a?(Hash)

      normalized = sticker.deep_dup.stringify_keys.slice(*TEMPLATE_STICKER_KEYS)
      next if normalized.empty?

      normalized["id"] = normalized["id"].presence || "tpl_#{idx}_#{SecureRandom.hex(6)}"
      normalized
    end
  end

  def apply_template_defaults_to_all_scenes!(scene_template_defaults)
    now = Time.current
    @project.screenshot_scenes.find_each do |scene|
      scene.update_columns(
        caption_text: scene_template_defaults[:caption_text],
        subtitle_text: scene_template_defaults[:subtitle_text],
        overrides: scene_template_defaults[:overrides].deep_dup,
        updated_at: now
      )
    end
  end

  def normalize_caption_layout_settings(settings)
    return settings unless settings.respond_to?(:to_h)

    normalized = settings.to_h.stringify_keys
    normalized["caption_mode"] = "zone"
    normalized["caption_position"] = "top"
    normalized
  end

  def normalize_store_upload_config(project:, target:, config:)
    normalized = config.to_h.stringify_keys

    # Custom Product Page uploads don't need locale validation — they use cpp_localization_id
    if target == "custom_product_page"
      unless normalized["cpp_localization_id"].present?
        return [ nil, "cpp_localization_id is required for custom_product_page uploads." ]
      end
      return [ normalized, nil ]
    end

    allowed_locales = Array(project.locales).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    default_locale = project.default_locale.to_s

    # Handle batch-locale upload: expand all_locales into the locales array
    if normalized.delete("all_locales").present? && allowed_locales.size > 1
      normalized["locales"] = allowed_locales
    end

    locale_key = target == "app_store_connect" ? "locale" : "language"
    valid_locales = target == "google_play" ? ScreenshotProject::GOOGLE_PLAY_LOCALES : ScreenshotProject::APP_STORE_LOCALES

    if normalized["locales"].present?
      # Batch-locale mode: validate all locales
      normalized["locales"].each do |loc|
        unless valid_locales.include?(loc)
          return [ nil, "Unsupported #{locale_key}: #{loc}." ]
        end
      end
      # Remove single locale/language key when using batch mode
      normalized.delete(locale_key)
    else
      # Single-locale mode (existing behavior)
      locale_value = normalized[locale_key].to_s.strip
      locale_value = default_locale if locale_value.blank?

      unless valid_locales.include?(locale_value)
        return [ nil, "Unsupported #{locale_key}: #{locale_value}." ]
      end

      if allowed_locales.any? && !allowed_locales.include?(locale_value)
        return [ nil, "#{locale_key.capitalize} must be one of this project's locales: #{allowed_locales.join(', ')}" ]
      end

      normalized[locale_key] = locale_value
    end

    [ normalized, nil ]
  end

  def render_plan_upgrade_required_json(required_plan:, message:, feature: "direct store uploads")
    current_plan = @organization.plan_tier

    render json: {
      error: "plan_upgrade_required",
      message: message,
      required_plan: required_plan.to_s,
      current_plan: current_plan.to_s,
      feature: feature,
      suggestion: plan_upgrade_suggestion(current_plan: current_plan, required_plan: required_plan),
      timestamp: Time.current.iso8601
    }, status: :forbidden
  end

  def render_quota_exhausted_json(message:, current_plan:, next_plan:, suggestion:, feature: nil)
    render json: {
      error: "quota_exhausted",
      message: message,
      current_plan: current_plan.to_s,
      next_plan: next_plan&.to_s,
      feature: feature,
      suggestion: suggestion,
      timestamp: Time.current.iso8601
    }.compact, status: :unprocessable_content
  end

  def plan_upgrade_suggestion(current_plan:, required_plan:)
    "Upgrade from #{current_plan.to_s.titleize} to #{required_plan.to_s.titleize} to enable automated store uploads."
  end

  def quota_upgrade_suggestion(current_plan:, next_plan:, feature:)
    current_name = current_plan.to_s.titleize

    if next_plan.present? && next_plan.to_s != current_plan.to_s
      "Upgrade from #{current_name} to #{next_plan.to_s.titleize} to increase the #{feature} limit."
    else
      "Your #{current_name} plan has reached its #{feature} limit. Wait for the limit window to reset or reduce usage."
    end
  end

  def set_project_create_gate_state(record = nil)
    probe = record || @organization.screenshot_projects.new(
      name: gate_probe_name("project"),
      platform: "both"
    )

    @project_create_gate = quota_gate_state(
      probe,
      source: "screenshot_projects#new:create-project"
    )
  end

  def gate_probe_name(prefix)
    "__#{prefix}_upgrade_gate_#{SecureRandom.hex(6)}__"
  end

  def human_storage_limit(bytes)
    ActiveSupport::NumberHelper.number_to_human_size(bytes)
  end

  def ensure_project_plan_access!
    return if @project.plan_accessible_on_current_plan?

    message = @project.plan_frozen_reason || "This screenshot project is frozen on the current plan."

    respond_to do |format|
      format.html do
        redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: message
      end
      format.json do
        render json: {
          error: "plan_frozen",
          message: message,
          current_plan: @organization.plan_tier.to_s,
          project_id: @project.id,
          project_name: @project.name,
          plan_access_state: @project.plan_access_state,
          frozen_project_ids: ScreenshotProject.plan_frozen_ids_for(@organization),
          accessible_project_ids: ScreenshotProject.plan_accessible_ids_for(@organization),
          suggestion: "Keep the oldest screenshot projects on the current plan or upgrade to unlock this project.",
          timestamp: Time.current.iso8601
        }, status: :forbidden
      end
      format.any { head :forbidden }
    end
  end

  def redirect_if_project_plan_frozen!
    return if @project.plan_accessible_on_current_plan?

    store_upgrade_prompt!(@project.plan_upgrade_prompt_payload(source: "#{controller_name}##{action_name}:project-access"))

    fallback_project = ScreenshotProject.oldest_plan_accessible_for(@organization)
    fallback_path =
      if fallback_project.present? && fallback_project.id != @project.id
        editor_organization_screenshot_project_path(@organization, fallback_project)
      else
        organization_screenshot_projects_path(@organization)
      end

    redirect_to fallback_path
  end

  def project_params
    params.require(:screenshot_project).permit(:name, :platform, :template, locales: [], settings: [
      :background_type, :background_color, :gradient_start, :gradient_end, :gradient_direction,
      :screenshot_padding, :screenshot_offset_y, :device_frame,
      :caption_font_size, :caption_color, :caption_position, :caption_font_family,
      :caption_font_weight, :caption_text_align, :caption_mode, :caption_zone_size,
      :caption_letter_spacing, :caption_line_height, :caption_vertical_position,
      :caption_text, :caption_stroke_enabled, :caption_stroke_color, :caption_stroke_width,
      :caption_gradient_enabled, :caption_gradient_start, :caption_gradient_end,
      :subtitle_font_size, :subtitle_color, :subtitle_font_family, :subtitle_font_weight,
      :subtitle_letter_spacing, :subtitle_line_height, :subtitle_text,
      :text_bg_enabled, :text_bg_color, :text_bg_opacity, :text_bg_radius,
      :text_bg_padding_x, :text_bg_padding_y,
      :mesh_preset, :mesh_color_1, :mesh_color_2, :mesh_color_3,
      :pattern_id, :pattern_color, :pattern_bg_color, :pattern_scale,
      :background_image_fit, :background_image_blur, :background_image_brightness,
      :perspective_preset, :perspective_rotate_x, :perspective_rotate_y,
      :perspective_distance, :perspective_shadow, :perspective_reflection,
      :layout_mode
    ])
  end
end
