class AppleDevicesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_device, only: [ :update ]

  def index
    authorize @organization, :show?

    @q_platform = params[:platform].presence
    @q_status = params[:status].presence
    @q_query = params[:q].to_s.strip.presence
    @show_register_modal = params[:register].present?

    # Table data - filter by selected team
    scope = AppleDevice.where(organization_id: @organization.id)
    # Include resources with null team_id OR matching team_id when filtering
    if selected_ios_team_id.present?
      scope = scope.where("team_id = ? OR team_id IS NULL", selected_ios_team_id)
    end
    scope = scope.where(platform: @q_platform) if @q_platform.present?
    scope = scope.where(status: @q_status) if @q_status.present?
    if @q_query
      scope = scope.where("name ILIKE :q OR udid ILIKE :q", q: "%#{@q_query}%")
    end

    @devices = scope.order(created_at: :desc).limit(1000)

    # Filter options from all teams
    @platforms = AppleDevice.where(organization_id: @organization.id).distinct.order(nil).pluck(:platform).compact
    @statuses = AppleDevice.where(organization_id: @organization.id).distinct.order(nil).pluck(:status).compact

    # Get team names for display
    @team_names = @organization.app_store_connect_credentials.where.not(team_id: nil).pluck(:team_id, :name).to_h

    respond_to do |format|
      format.html
      format.csv do
        send_data(devices_csv(@devices), filename: "devices-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}.csv", type: "text/csv; charset=utf-8")
      end
    end
  end

  def create
    authorize @organization, :manage_credentials? # gate by admin for now
    device_params = params.require(:device).permit(:name, :udid, :platform)

    # Use active ASC credential
    cred = @organization.app_store_connect_credentials.active.first
    if cred.nil?
      redirect_to organization_apple_devices_path(@organization), alert: "No active App Store credential"
      return
    end

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::Devices.new(client)
      resp = service.register(name: device_params[:name], platform: device_params[:platform], udid: device_params[:udid])
      attrs = resp.dig("data", "attributes") || {}
      AppleDevice.create!(
        organization_id: @organization.id,
        remote_id: resp.dig("data", "id"),
        name: attrs["name"] || device_params[:name],
        udid: attrs["udid"] || device_params[:udid],
        platform: attrs["platform"] || device_params[:platform],
        device_class: attrs["deviceClass"],
        status: attrs["status"],
        added_at: attrs["addedDate"],
        raw_json: JSON.dump(resp)
      )
      redirect_to organization_apple_devices_path(@organization), notice: "Device registered in App Store Connect"
    rescue => e
      redirect_to organization_apple_devices_path(@organization), alert: "Register failed: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def update
    authorize @organization, :manage_credentials?

    new_name = params.dig(:device, :name).to_s.strip
    if new_name.blank?
      respond_to do |format|
        format.html { redirect_to organization_apple_devices_path(@organization), alert: "Device name cannot be blank" }
        format.json { render json: { error: "Device name cannot be blank" }, status: :unprocessable_content }
      end
      return
    end

    cred = @organization.app_store_connect_credentials.active.first
    if cred.nil?
      respond_to do |format|
        format.html { redirect_to organization_apple_devices_path(@organization), alert: "No active App Store credential" }
        format.json { render json: { error: "No active App Store credential" }, status: :unprocessable_content }
      end
      return
    end

    begin
      client = AppStoreConnect::Client.new(credential: cred)
      service = AppStoreConnect::Devices.new(client)
      resp = service.update(device_id: @device.remote_id, name: new_name)

      attrs = resp.dig("data", "attributes") || {}
      @device.update!(
        name: attrs["name"] || new_name,
        raw_json: resp
      )

      respond_to do |format|
        format.html { redirect_to organization_apple_devices_path(@organization), notice: "Device renamed successfully" }
        format.json { render json: { success: true, name: @device.name } }
      end
    rescue => e
      respond_to do |format|
        format.html { redirect_to organization_apple_devices_path(@organization), alert: "Rename failed: #{ErrorMessageSanitizer.sanitize(e)}" }
        format.json { render json: { error: ErrorMessageSanitizer.sanitize(e) }, status: :unprocessable_content }
      end
    end
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_device
    @device = @organization.apple_devices.find(params[:id])
  end

  def devices_csv(devices)
    header = [ "name", "udid", "platform", "device_class", "status", "added_at" ]
    rows = [ csv_row(header) ]
    devices.each do |d|
      rows << csv_row([
        d.name,
        d.udid,
        d.platform,
        d.device_class,
        d.status,
        d.added_at&.iso8601
      ])
    end
    rows.join("\n") + "\n"
  end

  def csv_row(values)
    values.map { |v| v.to_s.gsub('"', '""') }.map { |v| "\"#{v}\"" }.join(",")
  end
end
