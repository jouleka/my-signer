class ScreenshotScenesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_project
  before_action :set_scene, only: [ :update, :destroy, :image, :thumbnail, :copy ]
  before_action :ensure_project_plan_access!, only: [ :create, :update, :copy, :bulk_update, :reorder ]

  MAX_FILE_SIZE = 10.megabytes
  MAX_FILES_PER_UPLOAD = 20

  def create
    authorize @organization, :manage_resources?

    files = Array(params[:screenshot_scene]&.[](:files) || [ params[:screenshot_scene]&.[](:file) ]).compact

    if files.empty?
      redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: "No files selected"
      return
    end

    if files.size > MAX_FILES_PER_UPLOAD
      redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: "Too many files (max #{MAX_FILES_PER_UPLOAD})"
      return
    end

    created_count = 0
    skipped = []
    media_quota_exceeded = false
    scene_limit_message = nil

    @organization.with_lock do
      @project.lock!

      scene_limit = @project.max_screenshot_scenes_per_project
      available_slots = scene_limit - @project.screenshot_scenes.count
      if available_slots <= 0
        scene_limit_message = "Project has reached the maximum of #{scene_limit} scenes"
        next
      end

      if files.size > available_slots
        scene_limit_message = "This project can only add #{available_slots} more scene#{'s' unless available_slots == 1}"
        next
      end

      validated_files = []
      total_incoming_bytes = 0

      files.each do |file|
        next unless file.respond_to?(:read)

        if file.size > MAX_FILE_SIZE
          skipped << "#{file.original_filename}: too large (max 10MB)"
          next
        end

        data = file.read

        # Validate image format by magic bytes
        unless data.byteslice(0, 4) == "\x89PNG".b || data.byteslice(0, 3) == "\xFF\xD8\xFF".b
          skipped << "#{file.original_filename}: not a valid PNG or JPEG"
          next
        end

        content_type = data.byteslice(0, 4) == "\x89PNG".b ? "image/png" : "image/jpeg"
        file.rewind

        total_incoming_bytes += file.size
        validated_files << { file: file, content_type: content_type, filename: file.original_filename }
      end

      if validated_files.empty?
        scene_limit_message = "No valid image files found"
        next
      end

      unless @project.org_within_media_quota?(total_incoming_bytes, use_cache: false)
        media_quota_exceeded = true
        next
      end

      validated_files.each do |entry|
        scene = @project.screenshot_scenes.new(
          source_image_content_type: entry[:content_type],
          source_image_filename: entry[:filename],
          source_image_width: params[:screenshot_scene]&.[](:width).to_i.nonzero?,
          source_image_height: params[:screenshot_scene]&.[](:height).to_i.nonzero?,
          caption_text: ""
        )
        scene.source_image.attach(
          io: entry[:file],
          filename: entry[:filename],
          content_type: entry[:content_type]
        )

        if scene.save
          created_count += 1
        else
          skipped << "#{entry[:filename]}: #{scene.errors.full_messages.to_sentence}"
        end
      end
    end

    if scene_limit_message.present?
      redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: scene_limit_message
    elsif media_quota_exceeded
      limit_label = ActiveSupport::NumberHelper.number_to_human_size(@project.max_media_storage_bytes_per_organization)
      store_upgrade_prompt!(
        plan_upgrade_prompt_payload(
          current_plan: @organization.plan_tier,
          required_plan: @organization.entitlements.next_plan_tier,
          feature: "screenshot media storage",
          message: "Organization screenshot media quota exceeded (max #{limit_label})",
          suggestion: upgrade_quota_suggestion(
            current_plan: @organization.plan_tier,
            next_plan: @organization.entitlements.next_plan_tier,
            feature: "screenshot media storage"
          )
        )
      )
      redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: "Organization screenshot media quota exceeded (max #{limit_label})"
    elsif created_count.positive? && skipped.empty?
      redirect_to editor_organization_screenshot_project_path(@organization, @project), notice: "Screenshot#{"s" if created_count > 1} uploaded"
    elsif created_count.positive?
      redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: "Uploaded #{created_count} file#{'s' unless created_count == 1}. Skipped: #{skipped.join(', ')}"
    else
      redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: skipped.presence&.join(", ") || "No files were uploaded"
    end
  end

  def update
    authorize @organization, :manage_resources?

    if @scene.update(scene_params)
      respond_to do |format|
        format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project) }
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: "Failed to update scene" }
        format.json { render json: { errors: @scene.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def destroy
    authorize @organization, :manage_resources?
    @scene.destroy
    @project.screenshot_scenes.order(:position).each_with_index do |scene, idx|
      scene.update_column(:position, idx + 1)
    end
    redirect_to editor_organization_screenshot_project_path(@organization, @project), notice: "Scene deleted"
  end

  def image
    authorize @organization, :show?

    if @scene.source_image.attached?
      blob = @scene.source_image.blob

      if stale?(etag: blob.checksum, last_modified: blob.created_at, public: false)
        expires_in 1.hour, private: true
        send_data blob.download,
                  type: blob.content_type,
                  disposition: "inline",
                  filename: blob.filename.to_s
      end
    elsif @scene.source_image_data.present?
      expires_in 1.hour, private: true
      send_data @scene.source_image_data,
                type: @scene.source_image_content_type || "image/png",
                disposition: "inline",
                filename: @scene.source_image_filename || "screenshot.png"
    else
      head :not_found
    end
  rescue ActiveStorage::FileNotFoundError
    Rails.logger.warn("Scene image blob missing for scene_id=#{@scene.id}")
    head :not_found
  end

  def thumbnail
    authorize @organization, :show?

    if @scene.source_image.attached?
      variant = @scene.source_image.variant(
        resize_to_fill: thumbnail_dimensions,
        format: :webp,
        saver: { quality: 82 }
      )
      variant.processed
      redirect_to rails_storage_proxy_path(variant, only_path: true), status: :found
    elsif @scene.source_image_data.present?
      expires_in 1.hour, private: true
      send_data @scene.source_image_data,
                type: @scene.source_image_content_type || "image/png",
                disposition: "inline"
    else
      head :not_found
    end
  rescue ActiveStorage::FileNotFoundError
    Rails.logger.warn("Scene thumbnail blob missing for scene_id=#{@scene.id}")
    head :not_found
  rescue LoadError => error
    handle_thumbnail_processing_error(error)
  rescue StandardError => error
    raise unless thumbnail_processing_error?(error)

    handle_thumbnail_processing_error(error)
  end

  def copy
    authorize @organization, :manage_resources?

    target_project = @organization.screenshot_projects.find(params[:target_project_id])

    if target_project.plan_frozen_on_current_plan?
      message = target_project.plan_frozen_reason || "Target screenshot project is frozen on the current plan."
      respond_to do |format|
        format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: message }
        format.json do
          render json: {
            error: "plan_frozen",
            message: message,
            current_plan: @organization.plan_tier.to_s,
            project_id: target_project.id,
            project_name: target_project.name,
            plan_access_state: target_project.plan_access_state,
            timestamp: Time.current.iso8601
          }, status: :forbidden
        end
      end
      return
    end

    new_scene = @scene.copy_to_project(target_project)

    if new_scene
      respond_to do |format|
        format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project), notice: "Scene copied to #{target_project.name}" }
        format.json { render json: { success: true, scene_id: new_scene.id } }
      end
    else
      respond_to do |format|
        format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: "Failed to copy scene" }
        format.json { render json: { errors: @scene.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def bulk_update
    authorize @organization, :manage_resources?

    scenes_data = params[:scenes] || []
    errors_list = []

    ActiveRecord::Base.transaction do
      scenes_data.each do |scene_data|
        scene = @project.screenshot_scenes.find_by(id: scene_data[:id])
        next unless scene

        attrs = { caption_text: scene_data[:caption_text], subtitle_text: scene_data[:subtitle_text] }
        attrs[:locale_variants] = sanitize_locale_variants(scene_data[:locale_variants]) if scene_data[:locale_variants].present?

        unless scene.update(attrs)
          errors_list << { id: scene.id, errors: scene.errors.full_messages }
        end
      end

      raise ActiveRecord::Rollback if errors_list.any?
    end

    if errors_list.empty?
      respond_to do |format|
        format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project), notice: "All scenes updated" }
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project), alert: "Some scenes failed to update" }
        format.json { render json: { errors: errors_list }, status: :unprocessable_content }
      end
    end
  end

  def reorder
    authorize @organization, :manage_resources?

    positions = params[:positions] || []
    positions.each do |item|
      id = item[:id].to_i
      position = item[:position].to_i
      next if id <= 0 || position <= 0

      @project.screenshot_scenes.where(id: id).update_all(position: position)
    end

    respond_to do |format|
      format.html { redirect_to editor_organization_screenshot_project_path(@organization, @project) }
      format.json { render json: { success: true } }
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
    @project = @organization.screenshot_projects.find(params[:screenshot_project_id])
  end

  def set_scene
    @scene = @project.screenshot_scenes.find(params[:id])
  end

  def thumbnail_dimensions
    width = params[:w].to_i
    height = params[:h].to_i
    width = 96 unless width.between?(40, 800)
    height = 170 unless height.between?(70, 1600)
    [ width, height ]
  end

  def thumbnail_processing_error?(error)
    transformation_error = ActiveStorage::Transformers::ImageProcessingTransformer::UnsupportedImageProcessingMethod

    current = error
    while current
      return true if current.is_a?(LoadError)
      return true if current.is_a?(transformation_error)
      return true if defined?(MiniMagick::Error) && current.is_a?(MiniMagick::Error)
      return true if defined?(MiniMagick::Invalid) && current.is_a?(MiniMagick::Invalid)

      current = current.cause
    end

    false
  end

  def handle_thumbnail_processing_error(error)
    Rails.logger.warn(
      "Scene thumbnail processing unavailable for scene_id=#{@scene.id}: #{error.class}: #{error.message}. " \
      "Falling back to the original image. Install libvips locally to restore transformed thumbnails."
    )
    redirect_to image_organization_screenshot_project_screenshot_scene_path(@organization, @project, @scene), status: :found
  end

  def scene_params
    permitted = params.require(:screenshot_scene).permit(:caption_text, :subtitle_text, overrides: {})
    if permitted[:overrides].present?
      permitted[:overrides] = sanitize_overrides(permitted[:overrides])
    end
    if params[:screenshot_scene][:locale_variants].present?
      permitted[:locale_variants] = sanitize_locale_variants(params[:screenshot_scene][:locale_variants])
    end
    permitted
  end

  ALLOWED_OVERRIDE_KEYS = %w[
    caption_color caption_font_size subtitle_color subtitle_font_size
    text_position_x text_position_y text_rotation
    background_type background_color gradient_start gradient_end gradient_direction
    screenshot_padding screenshot_offset_y caption_position device_frame
    caption_font_family caption_font_weight caption_text_align caption_mode
    caption_zone_size caption_letter_spacing caption_line_height caption_vertical_position
    subtitle_font_family subtitle_font_weight subtitle_letter_spacing subtitle_line_height
    text_bg_enabled text_bg_color text_bg_opacity text_bg_radius
    text_bg_padding_x text_bg_padding_y
    caption_stroke_enabled caption_stroke_color caption_stroke_width
    caption_gradient_enabled caption_gradient_start caption_gradient_end
    mesh_preset mesh_color_1 mesh_color_2 mesh_color_3
    pattern_id pattern_color pattern_bg_color pattern_scale
    background_image_fit background_image_blur background_image_brightness
    perspective_preset perspective_rotate_x perspective_rotate_y perspective_distance
    perspective_shadow perspective_reflection
    layout_mode
    stickers
  ].freeze

  MAX_STICKERS_PER_SCENE = 20
  ALLOWED_STICKER_KEYS = %w[id type emoji asset_key image_url x y size rotation color text bgColor bgEnabled fontWeight].freeze
  VALID_ASSET_KEYS = ScreenshotProject::STICKER_LIBRARY.values.flat_map { |cat| cat[:items].map { |i| i[:key] } }.to_set.freeze

  def sanitize_overrides(overrides)
    raw = overrides.respond_to?(:to_unsafe_h) ? overrides.to_unsafe_h : overrides.to_h
    sanitized = raw.slice(*ALLOWED_OVERRIDE_KEYS)
    sanitized["caption_mode"] = "zone" if sanitized.key?("caption_mode")
    sanitized["caption_position"] = "top" if sanitized.key?("caption_position")

    if sanitized["stickers"].present?
      sanitized["stickers"] = Array(sanitized["stickers"]).map do |sticker|
        sticker = sticker.respond_to?(:to_unsafe_h) ? sticker.to_unsafe_h : sticker.to_h
        s = sticker.slice(*ALLOWED_STICKER_KEYS).transform_keys(&:to_s)
        s["emoji"] = s["emoji"].to_s[0..20] if s["emoji"]
        s["text"] = s["text"].to_s[0..200] if s["text"]
        s["x"] = s["x"].to_f.clamp(0, 100) if s["x"]
        s["y"] = s["y"].to_f.clamp(0, 100) if s["y"]
        s["size"] = s["size"].to_f.clamp(10, 500) if s["size"]
        s["rotation"] = s["rotation"].to_f.clamp(-180, 180) if s["rotation"]
        s
      end.select { |s|
        s["emoji"].present? ||
        (s["asset_key"].present? && VALID_ASSET_KEYS.include?(s["asset_key"])) ||
        (s["type"] == "custom_image" && s["image_url"].present?) ||
        (s["type"] == "text" && s["text"].present?)
      }.first(MAX_STICKERS_PER_SCENE)
    end

    sanitized
  end

  ALLOWED_LOCALE_VARIANT_KEYS = %w[caption_text subtitle_text].freeze
  MAX_LOCALE_VARIANTS = 50
  MAX_LOCALE_TEXT_LENGTH = 500

  def sanitize_locale_variants(variants)
    return {} unless variants.respond_to?(:to_unsafe_h) || variants.is_a?(Hash)

    raw = variants.respond_to?(:to_unsafe_h) ? variants.to_unsafe_h : variants
    result = {}

    raw.each do |locale, fields|
      break if result.size >= MAX_LOCALE_VARIANTS
      next unless fields.is_a?(Hash)

      locale_str = locale.to_s
      next unless locale_str.match?(/\A[a-zA-Z]{2}(-[a-zA-Z]{2,4})?\z/)

      sanitized_fields = fields.slice(*ALLOWED_LOCALE_VARIANT_KEYS).transform_keys(&:to_s)
      sanitized_fields.each do |key, value|
        sanitized_fields[key] = value.to_s[0, MAX_LOCALE_TEXT_LENGTH]
      end

      result[locale_str] = sanitized_fields
    end

    result
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
          timestamp: Time.current.iso8601
        }, status: :forbidden
      end
      format.any { head :forbidden }
    end
  end
end
