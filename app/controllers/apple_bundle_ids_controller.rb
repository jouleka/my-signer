class AppleBundleIdsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_bundle_id, only: [ :show, :enable_capability, :disable_capability, :register_app_group, :associate_app_group, :dissociate_app_group ]

  def index
    authorize @organization, :show?

    @q_platform = params[:platform].presence
    @q_query = params[:q].to_s.strip.presence

    # Stats - ALWAYS show total across ALL teams (for the header box)
    @total_bundle_ids = @organization.apple_bundle_ids.count
    @with_capabilities = @organization.apple_bundle_ids.joins(:apple_bundle_id_capabilities).distinct.count

    # Table data - filter by selected team
    scope = AppleBundleId.where(organization_id: @organization.id)
    if selected_ios_team_id.present?
      scope = scope.where("team_id = ? OR team_id IS NULL", selected_ios_team_id)
    end
    scope = scope.where(platform: @q_platform) if @q_platform.present?
    if @q_query
      scope = scope.where("identifier ILIKE :q OR name ILIKE :q", q: "%#{@q_query}%")
    end

    @bundle_ids = scope.includes(:apple_bundle_id_capabilities).order(identifier: :asc).limit(500)

    # Filter options from all teams
    @platforms = AppleBundleId.where(organization_id: @organization.id).distinct.order(nil).pluck(:platform).compact

    # Get team names for display
    @team_names = @organization.app_store_connect_credentials.where.not(team_id: nil).pluck(:team_id, :name).to_h
  end

  def show
    authorize @organization, :show?

    @capabilities = @bundle_id.apple_bundle_id_capabilities.sorted
    @available_capabilities = AppleBundleIdCapability::CAPABILITY_TYPES - @capabilities.pluck(:capability_type)
    @profiles = @organization.apple_provisioning_profiles.where(bundle_id_identifier: @bundle_id.identifier)

    # Load current associations
    @associated_app_groups = @bundle_id.apple_app_groups
    @associated_merchant_ids = @bundle_id.apple_merchant_ids

    # Load available app groups for manual association (not already associated)
    @available_app_groups = @organization.apple_app_groups.where.not(id: @associated_app_groups.pluck(:id))

    # Check if APP_GROUPS capability is enabled
    @has_app_groups_capability = @capabilities.exists?(capability_type: "APP_GROUPS")
  end

  def new
    authorize @organization, :manage_credentials?
  end

  def create
    authorize @organization, :manage_credentials?

    bundle_id_params = params.require(:bundle_id).permit(:identifier, :name, :platform)

    cred = @organization.app_store_connect_credentials.active.first
    if cred.nil?
      redirect_to organization_apple_bundle_ids_path(@organization), alert: "No active App Store credential"
      return
    end

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::BundleIds.new(client)
      resp = service.register(
        identifier: bundle_id_params[:identifier],
        name: bundle_id_params[:name],
        platform: bundle_id_params[:platform]
      )

      attrs = resp.dig("data", "attributes") || {}
      AppleBundleId.create!(
        organization_id: @organization.id,
        remote_id: resp.dig("data", "id"),
        identifier: attrs["identifier"] || bundle_id_params[:identifier],
        name: attrs["name"] || bundle_id_params[:name],
        platform: attrs["platform"] || bundle_id_params[:platform],
        team_id: cred.team_id,
        raw_json: resp
      )

      # Trigger async sync to refresh
      AppStoreConnectSyncJob.perform_later(@organization.id)

      redirect_to organization_apple_bundle_ids_path(@organization), notice: "Bundle ID registered successfully."
    rescue => e
      redirect_to new_organization_apple_bundle_id_path(@organization), alert: "Registration failed: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def enable_capability
    authorize @organization, :manage_credentials?

    capability_type = params[:capability_type]
    unless AppleBundleIdCapability::CAPABILITY_TYPES.include?(capability_type)
      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "Invalid capability type"
      return
    end

    cred = @organization.app_store_connect_credentials.active.first
    if cred.nil?
      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "No active App Store credential"
      return
    end

    # Build capability settings (only for ICLOUD and DATA_PROTECTION)
    # Note: APP_GROUPS and APPLE_PAY must be configured in Apple Developer Portal
    settings = build_capability_settings(capability_type)

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::BundleIds.new(client)
      resp = service.enable_capability(
        bundle_id_remote_id: @bundle_id.remote_id,
        capability_type: capability_type,
        settings: settings
      )

      attrs = resp.dig("data", "attributes") || {}
      AppleBundleIdCapability.create!(
        apple_bundle_id: @bundle_id,
        remote_id: resp.dig("data", "id"),
        capability_type: attrs["capabilityType"] || capability_type,
        settings: attrs["settings"] || {},
        raw_json: resp
      )

      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), notice: "Capability enabled successfully."
    rescue => e
      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "Failed to enable capability: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def disable_capability
    authorize @organization, :manage_credentials?

    capability = @bundle_id.apple_bundle_id_capabilities.find(params[:capability_id])

    cred = @organization.app_store_connect_credentials.active.first
    if cred.nil?
      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "No active App Store credential"
      return
    end

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::BundleIds.new(client)
      service.disable_capability(capability_remote_id: capability.remote_id)

      capability.destroy!

      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), notice: "Capability disabled successfully."
    rescue => e
      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "Failed to disable capability: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  # Register a new App Group and associate it with this Bundle ID
  # Note: Apple's API doesn't expose app groups, so this is a local-only operation.
  # The user must also create this App Group in the Apple Developer Portal.
  def register_app_group
    authorize @organization, :manage_credentials?

    identifier = params[:identifier].to_s.strip

    unless identifier.start_with?("group.")
      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "App Group identifier must start with 'group.'"
      return
    end

    cred = @organization.app_store_connect_credentials.active.first
    team_id = cred&.team_id

    ActiveRecord::Base.transaction do
      # Find or create the app group
      app_group = @organization.apple_app_groups.find_or_create_by!(identifier: identifier) do |ag|
        ag.name = identifier
        ag.team_id = team_id
      end

      # Associate with bundle ID (if not already)
      unless @bundle_id.apple_app_groups.include?(app_group)
        AppleBundleIdAppGroup.create!(
          apple_bundle_id: @bundle_id,
          apple_app_group: app_group
        )
      end

      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), notice: "App Group '#{identifier}' registered and associated."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "Failed to register App Group: #{ErrorMessageSanitizer.sanitize(e)}"
  rescue => e
    redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "Failed to register App Group: #{ErrorMessageSanitizer.sanitize(e)}"
  end

  # Manually associate an App Group with this Bundle ID
  # Note: Apple's API doesn't expose app group associations, so this is a local-only operation.
  # The user must also configure this association in the Apple Developer Portal.
  def associate_app_group
    authorize @organization, :manage_credentials?

    app_group = @organization.apple_app_groups.find(params[:app_group_id])

    # Check if already associated
    if @bundle_id.apple_app_groups.include?(app_group)
      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), notice: "App Group is already associated."
      return
    end

    AppleBundleIdAppGroup.create!(
      apple_bundle_id: @bundle_id,
      apple_app_group: app_group
    )

    redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), notice: "App Group '#{app_group.identifier}' associated successfully."
  rescue ActiveRecord::RecordNotFound
    redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "App Group not found."
  rescue => e
    redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "Failed to associate App Group: #{ErrorMessageSanitizer.sanitize(e)}"
  end

  # Remove an App Group association from this Bundle ID
  # Note: This is a local-only operation. The user must also remove this association in the Apple Developer Portal.
  def dissociate_app_group
    authorize @organization, :manage_credentials?

    app_group = @organization.apple_app_groups.find(params[:app_group_id])
    association = @bundle_id.apple_bundle_id_app_groups.find_by(apple_app_group: app_group)

    if association.nil?
      redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "App Group association not found."
      return
    end

    association.destroy!

    redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), notice: "App Group '#{app_group.identifier}' removed from this Bundle ID."
  rescue ActiveRecord::RecordNotFound
    redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "App Group not found."
  rescue => e
    redirect_to organization_apple_bundle_id_path(@organization, @bundle_id), alert: "Failed to remove App Group: #{ErrorMessageSanitizer.sanitize(e)}"
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_bundle_id
    @bundle_id = @organization.apple_bundle_ids.find(params[:id])
  end

  # Build settings for capabilities that support API configuration
  # Note: APP_GROUPS and APPLE_PAY must be configured in Apple Developer Portal
  # (their associations cannot be managed via App Store Connect API)
  def build_capability_settings(capability_type)
    case capability_type
    when "ICLOUD"
      icloud_version = params[:icloud_version]
      return nil unless icloud_version.in?(%w[XCODE_5 XCODE_6])

      [ {
        key: "ICLOUD_VERSION",
        options: [ { key: icloud_version, enabled: true } ]
      } ]
    when "DATA_PROTECTION"
      protection_level = params[:data_protection_level]
      valid_levels = %w[COMPLETE_PROTECTION PROTECTED_UNLESS_OPEN PROTECTED_UNTIL_FIRST_USER_AUTH]
      return nil unless protection_level.in?(valid_levels)

      [ {
        key: "DATA_PROTECTION_PERMISSION_LEVEL",
        options: [ { key: protection_level, enabled: true } ]
      } ]
    else
      # Most capabilities don't require settings
      nil
    end
  end
end
