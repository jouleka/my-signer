class AppleProvisioningProfilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_profile, only: [ :show, :download, :destroy, :regenerate ]

  def index
    authorize @organization, :show?

    @q_type = params[:type].presence
    @q_state = params[:state].presence
    @q_query = params[:q].to_s.strip.presence

    # Table data - filter by selected team
    scope = AppleProvisioningProfile.where(organization_id: @organization.id)
    # Include resources with null team_id OR matching team_id when filtering
    if selected_ios_team_id.present?
      scope = scope.where("team_id = ? OR team_id IS NULL", selected_ios_team_id)
    end
    scope = scope.where(profile_type: @q_type) if @q_type.present?
    scope = scope.where(state: @q_state) if @q_state.present?
    if @q_query
      scope = scope.where("name ILIKE :q OR uuid ILIKE :q", q: "%#{@q_query}%")
    end

    @profiles = scope.order(expires_at: :asc, name: :asc).limit(500)

    # Filter options from all teams
    @types = AppleProvisioningProfile.where(organization_id: @organization.id).distinct.order(nil).pluck(:profile_type).compact
    @states = AppleProvisioningProfile.where(organization_id: @organization.id).distinct.order(nil).pluck(:state).compact

    # Get team names for display
    @team_names = @organization.app_store_connect_credentials.where.not(team_id: nil).pluck(:team_id, :name).to_h
  end

  def new
    authorize @organization, :manage_credentials?

    @bundle_ids = AppleBundleId.where(organization_id: @organization.id).order(:identifier)
    @certificates = AppleCertificate.where(organization_id: @organization.id).order(:name)
    @devices = AppleDevice.where(organization_id: @organization.id, status: "ENABLED").order(:name)
  end

  def create
    authorize @organization, :manage_credentials?

    permitted = params.require(:profile).permit(:name, :profile_type, :bundle_id_id, certificate_ids: [], device_ids: [])

    # Validate required fields
    if permitted[:bundle_id_id].blank?
      redirect_to new_organization_apple_provisioning_profile_path(@organization), alert: "Bundle ID is required"
      return
    end

    if Array(permitted[:certificate_ids]).reject(&:blank?).empty?
      redirect_to new_organization_apple_provisioning_profile_path(@organization), alert: "At least one certificate is required"
      return
    end

    cred = @organization.app_store_connect_credentials.active.first
    if cred.nil?
      redirect_to new_organization_apple_provisioning_profile_path(@organization), alert: "No active App Store credential"
      return
    end

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::Profiles.new(client)
      resp = service.create(
        name: permitted[:name],
        profile_type: permitted[:profile_type],
        bundle_id_id: permitted[:bundle_id_id],
        certificate_ids: Array(permitted[:certificate_ids]).reject(&:blank?),
        device_ids: Array(permitted[:device_ids]).reject(&:blank?)
      )

      # Persist minimal placeholder; a background sync will enrich
      attrs = resp.dig("data", "attributes") || {}
      AppleProvisioningProfile.create!(
        organization_id: @organization.id,
        remote_id: resp.dig("data", "id"),
        name: attrs["name"] || permitted[:name],
        uuid: attrs["uuid"],
        profile_type: attrs["profileType"] || permitted[:profile_type],
        state: attrs["profileState"],
        platform: attrs["platform"],
        bundle_id_identifier: permitted[:bundle_id_id],
        expires_at: (attrs["expirationDate"] rescue nil),
        raw_json: JSON.dump(resp)
      )

      # Trigger async sync to refresh
      AppStoreConnectSyncJob.perform_later(@organization.id)

      redirect_to organization_apple_provisioning_profiles_path(@organization), notice: "Profile created. Sync triggered to refresh data."
    rescue => e
      redirect_to new_organization_apple_provisioning_profile_path(@organization), alert: "Create failed: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def show
    authorize @organization, :show?

    # Parse raw_json to extract included certificates and devices if available
    @included_certificates = []
    @included_devices = []
    @bundle_id_info = nil

    begin
      raw = JSON.parse(@profile.raw_json.is_a?(String) ? @profile.raw_json : @profile.raw_json.to_json)
      included = raw["included"] || []

      included.each do |item|
        case item["type"]
        when "certificates"
          attrs = item["attributes"] || {}
          @included_certificates << {
            id: item["id"],
            name: attrs["name"],
            type: attrs["certificateType"],
            serial_number: attrs["serialNumber"],
            expires_at: attrs["expirationDate"]
          }
        when "devices"
          attrs = item["attributes"] || {}
          @included_devices << {
            id: item["id"],
            name: attrs["name"],
            udid: attrs["udid"],
            platform: attrs["platform"],
            device_class: attrs["deviceClass"],
            status: attrs["status"]
          }
        when "bundleIds"
          attrs = item["attributes"] || {}
          @bundle_id_info = {
            id: item["id"],
            identifier: attrs["identifier"],
            name: attrs["name"],
            platform: attrs["platform"]
          }
        end
      end
    rescue => e
      Rails.logger.warn("Could not parse profile raw_json for included data: #{e.message}")
    end

    # If we don't have included data, try to fetch from API
    if @included_certificates.empty? && @included_devices.empty?
      fetch_profile_details_from_api
    end

    # Get the linked bundle ID record
    @bundle_id = @organization.apple_bundle_ids.find_by(identifier: @profile.bundle_id_identifier)
  end

  def download
    authorize @organization, :show?
    raw = begin
      JSON.parse(@profile.raw_json)
    rescue
      nil
    end
    content = nil
    if raw.is_a?(Hash)
      content = raw.dig("attributes", "profileContent") || raw.dig("data", "attributes", "profileContent")
    end
    return redirect_to(organization_apple_provisioning_profiles_path(@organization), alert: "No content available") if content.blank?

    data = begin
      Base64.strict_decode64(content)
    rescue
      Base64.decode64(content)
    end
    send_data(data, filename: "#{@profile.name}.mobileprovision", type: "application/octet-stream")
  end

  def destroy
    authorize @organization, :manage_credentials?

    cred = @organization.app_store_connect_credentials.active.first
    if cred.nil?
      redirect_to organization_apple_provisioning_profiles_path(@organization), alert: "No active App Store credential"
      return
    end

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::Profiles.new(client)
      service.delete(@profile.remote_id)

      @profile.destroy!

      redirect_to organization_apple_provisioning_profiles_path(@organization), notice: "Profile deleted successfully."
    rescue => e
      redirect_to organization_apple_provisioning_profile_path(@organization, @profile), alert: "Failed to delete profile: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def regenerate
    authorize @organization, :manage_credentials?

    cred = @organization.app_store_connect_credentials.active.first
    if cred.nil?
      redirect_to organization_apple_provisioning_profile_path(@organization, @profile), alert: "No active App Store credential"
      return
    end

    # Store profile info before deletion
    profile_name = @profile.name
    profile_type = @profile.profile_type

    # Get the bundle ID
    bundle_id = @organization.apple_bundle_ids.find_by(identifier: @profile.bundle_id_identifier)
    if bundle_id.nil?
      redirect_to organization_apple_provisioning_profile_path(@organization, @profile), alert: "Bundle ID not found"
      return
    end

    # Parse existing profile to get certificate and device IDs
    certificate_ids = []
    device_ids = []

    begin
      raw = JSON.parse(@profile.raw_json.is_a?(String) ? @profile.raw_json : @profile.raw_json.to_json)
      included = raw["included"] || []

      included.each do |item|
        case item["type"]
        when "certificates"
          certificate_ids << item["id"]
        when "devices"
          device_ids << item["id"]
        end
      end
    rescue => e
      Rails.logger.warn("Could not parse profile raw_json: #{e.message}")
    end

    # If we don't have certificate/device IDs from raw_json, try to fetch from API
    if certificate_ids.empty?
      fetch_result = fetch_profile_relationships_from_api
      if fetch_result
        certificate_ids = fetch_result[:certificate_ids]
        device_ids = fetch_result[:device_ids]
      end
    end

    if certificate_ids.empty?
      redirect_to organization_apple_provisioning_profile_path(@organization, @profile), alert: "Could not determine certificates for regeneration"
      return
    end

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::Profiles.new(client)

      # Delete old profile
      service.delete(@profile.remote_id)
      @profile.destroy!

      # Create new profile with same configuration
      resp = service.create(
        name: profile_name,
        profile_type: profile_type,
        bundle_id_id: bundle_id.remote_id,
        certificate_ids: certificate_ids,
        device_ids: device_ids
      )

      attrs = resp.dig("data", "attributes") || {}
      AppleProvisioningProfile.create!(
        organization_id: @organization.id,
        remote_id: resp.dig("data", "id"),
        name: attrs["name"] || profile_name,
        uuid: attrs["uuid"],
        profile_type: attrs["profileType"] || profile_type,
        state: attrs["profileState"],
        platform: attrs["platform"],
        bundle_id_identifier: bundle_id.identifier,
        expires_at: (attrs["expirationDate"] rescue nil),
        team_id: cred.team_id,
        raw_json: resp
      )

      # Trigger async sync to refresh
      AppStoreConnectSyncJob.perform_later(@organization.id)

      redirect_to organization_apple_provisioning_profiles_path(@organization), notice: "Profile regenerated successfully."
    rescue => e
      redirect_to organization_apple_provisioning_profiles_path(@organization), alert: "Failed to regenerate profile: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  private

  def fetch_profile_details_from_api
    cred = @organization.app_store_connect_credentials.active.first
    return unless cred

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::Profiles.new(client)
      resp = service.show(@profile.remote_id)

      included = resp["included"] || []
      included.each do |item|
        case item["type"]
        when "certificates"
          attrs = item["attributes"] || {}
          @included_certificates << {
            id: item["id"],
            name: attrs["name"],
            type: attrs["certificateType"],
            serial_number: attrs["serialNumber"],
            expires_at: attrs["expirationDate"]
          }
        when "devices"
          attrs = item["attributes"] || {}
          @included_devices << {
            id: item["id"],
            name: attrs["name"],
            udid: attrs["udid"],
            platform: attrs["platform"],
            device_class: attrs["deviceClass"],
            status: attrs["status"]
          }
        when "bundleIds"
          attrs = item["attributes"] || {}
          @bundle_id_info = {
            id: item["id"],
            identifier: attrs["identifier"],
            name: attrs["name"],
            platform: attrs["platform"]
          }
        end
      end

      # Update the stored raw_json with the full response
      @profile.update(raw_json: resp)
    rescue => e
      Rails.logger.warn("Could not fetch profile details from API: #{e.message}")
    end
  end

  def fetch_profile_relationships_from_api
    cred = @organization.app_store_connect_credentials.active.first
    return nil unless cred

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::Profiles.new(client)
      resp = service.show(@profile.remote_id)

      certificate_ids = []
      device_ids = []

      included = resp["included"] || []
      included.each do |item|
        case item["type"]
        when "certificates"
          certificate_ids << item["id"]
        when "devices"
          device_ids << item["id"]
        end
      end

      { certificate_ids: certificate_ids, device_ids: device_ids }
    rescue => e
      Rails.logger.warn("Could not fetch profile relationships from API: #{e.message}")
      nil
    end
  end

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_profile
    @profile = @organization.apple_provisioning_profiles.find(params[:id])
  end
end
