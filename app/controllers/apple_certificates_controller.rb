class AppleCertificatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_certificate, only: [ :show, :download ]

  def index
    authorize @organization, :show?

    @q_type = params[:type].presence
    @q_platform = params[:platform].presence
    @q_query = params[:q].to_s.strip.presence

    # Stats - ALWAYS show total across ALL teams (for the header box)
    @total_certificates = @organization.apple_certificates.count
    @expiring_certificates = @organization.apple_certificates.where("expires_at IS NOT NULL AND expires_at <= ?", 30.days.from_now).count

    # Table data - filter by selected team
    scope = AppleCertificate.where(organization_id: @organization.id)
    # Include resources with null team_id OR matching team_id when filtering
    if selected_ios_team_id.present?
      scope = scope.where("team_id = ? OR team_id IS NULL", selected_ios_team_id)
    end
    scope = scope.where(certificate_type: @q_type) if @q_type.present?
    scope = scope.where(platform: @q_platform) if @q_platform.present?
    if @q_query
      scope = scope.where("name ILIKE :q OR serial_number ILIKE :q", q: "%#{@q_query}%")
    end

    @certificates = scope.order(expires_at: :asc, name: :asc).limit(500)

    # Option sets (from all teams)
    @types = AppleCertificate.where(organization_id: @organization.id).distinct.order(nil).pluck(:certificate_type).compact
    @platforms = AppleCertificate.where(organization_id: @organization.id).distinct.order(nil).pluck(:platform).compact

    # Get team names for display
    @team_names = @organization.app_store_connect_credentials.where.not(team_id: nil).pluck(:team_id, :name).to_h
  end

  def show
    authorize @organization, :show?

    # Find profiles using this certificate
    @profiles = @organization.apple_provisioning_profiles.select do |profile|
      begin
        raw = JSON.parse(profile.raw_json.is_a?(String) ? profile.raw_json : profile.raw_json.to_json)
        included = raw["included"] || []
        included.any? { |item| item["type"] == "certificates" && item["id"] == @certificate.remote_id }
      rescue
        false
      end
    end

    # Get team name for display
    @team_name = if @certificate.team_id.present?
      @organization.app_store_connect_credentials.find_by(team_id: @certificate.team_id)&.name
    end
  end

  def download
    authorize @organization, :show?

    raw = begin
      parsed = JSON.parse(@certificate.raw_json.is_a?(String) ? @certificate.raw_json : @certificate.raw_json.to_json)
      parsed.is_a?(Hash) && parsed.key?("data") ? parsed : { "data" => parsed }
    rescue
      nil
    end

    content = nil
    if raw.is_a?(Hash)
      content = raw.dig("data", "attributes", "certificateContent") || raw.dig("attributes", "certificateContent")
    end

    if content.blank?
      redirect_to organization_apple_certificate_path(@organization, @certificate), alert: "No certificate content available. The certificate data may not include the downloadable content."
      return
    end

    data = begin
      Base64.strict_decode64(content)
    rescue
      Base64.decode64(content)
    end

    filename = "#{@certificate.name.parameterize}.cer"
    send_data(data, filename: filename, type: "application/x-x509-ca-cert")
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_certificate
    @certificate = @organization.apple_certificates.find(params[:id])
  end
end
