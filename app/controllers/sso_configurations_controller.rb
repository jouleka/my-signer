class SsoConfigurationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  # Entitlement check runs FIRST (before set_config and Pundit) so non-Team
  # users see a friendly paywall page on every SSO route, including the
  # `set_config`-redirected paths. Without this, Pro admins get bounced
  # through the redirect-to-new path and then hit Pundit's generic denial.
  before_action :require_sso_entitlement!
  before_action :set_config, only: [ :show, :edit, :update, :destroy ]
  after_action :verify_authorized

  # GET /organizations/:id/sso_configuration
  def show
    authorize @organization, :show?, policy_class: SsoConfigurationPolicy
    set_current_organization!(@organization)
  end

  # GET /organizations/:id/sso_configuration/new
  def new
    @config = @organization.build_sso_configuration
    authorize @organization, :new?, policy_class: SsoConfigurationPolicy
  end

  # POST /organizations/:id/sso_configuration
  def create
    authorize @organization, :create?, policy_class: SsoConfigurationPolicy
    @config = @organization.build_sso_configuration(sso_config_params)

    if @config.save
      Audit::Logger.log(
        action: "sso_configuration_created",
        actor: current_user,
        organization: @organization,
        resource: @config,
        metadata: { idp_entity_id: @config.idp_entity_id },
        request: request
      )
      SsoConfigurationChangedNotificationJob.perform_later(
        organization_id: @organization.id,
        actor_id: current_user.id,
        event: "created"
      )
      redirect_to organization_sso_configuration_path(@organization),
        notice: "SSO configuration saved."
    else
      render :new, status: :unprocessable_content
    end
  end

  # GET /organizations/:id/sso_configuration/edit
  def edit
    authorize @organization, :edit?, policy_class: SsoConfigurationPolicy
  end

  # PATCH /organizations/:id/sso_configuration
  def update
    authorize @organization, :update?, policy_class: SsoConfigurationPolicy

    if @config.update(sso_config_params)
      Audit::Logger.log(
        action: "sso_configuration_updated",
        actor: current_user,
        organization: @organization,
        resource: @config,
        metadata: { idp_entity_id: @config.idp_entity_id, enforced: @config.enforced, enabled: @config.enabled },
        request: request
      )
      SsoConfigurationChangedNotificationJob.perform_later(
        organization_id: @organization.id,
        actor_id: current_user.id,
        event: "updated"
      )
      redirect_to organization_sso_configuration_path(@organization),
        notice: "SSO configuration updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /organizations/:id/sso_configuration
  def destroy
    authorize @organization, :destroy?, policy_class: SsoConfigurationPolicy

    @config.destroy
    Audit::Logger.log(
      action: "sso_configuration_removed",
      actor: current_user,
      organization: @organization,
      metadata: {},
      request: request
    )
    SsoConfigurationChangedNotificationJob.perform_later(
      organization_id: @organization.id,
      actor_id: current_user.id,
      event: "removed"
    )
    redirect_to organization_path(@organization),
      notice: "SSO configuration removed."
  end

  private

  def set_org
    # Scope to memberships so non-member access returns 404 before the
    # feature-gate renders the paywall (which would echo org name + plan
    # tier into the DOM — a cross-org enumeration oracle otherwise).
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def require_sso_entitlement!
    return if @organization.entitlements.sso_enabled?

    render_team_feature_paywall!(
      name: "Single Sign-On (SAML 2.0)",
      icon: "fa-id-card-clip",
      description: "Let your team sign in with your existing identity provider — Okta, Microsoft Entra ID, Google Workspace, or any SAML 2.0 IdP.",
      bullets: [
        "SAML 2.0 with all major identity providers",
        "Just-in-time user provisioning",
        "Per-org configuration (multiple orgs supported)",
        "Optional enforcement (block password login)",
        "Encrypted IdP certificate at rest",
        "Owner break-glass access (never get locked out)",
        "Audit log for every SSO sign-in",
        "Public SP metadata XML for IdP auto-config"
      ]
    )
  end

  def set_config
    @config = @organization.sso_configuration
    redirect_to new_organization_sso_configuration_path(@organization) if @config.nil? && action_name != "new" && action_name != "create"
  end

  # Only these mapping target keys are consumed by SsoConfiguration#effective_attribute_mappings
  # and Sso::JitProvisioner. Adding new keys here without a corresponding consumer is dead config;
  # `permit!` (mass assignment) was previously used here -- avoid that, enumerate explicitly.
  ATTRIBUTE_MAPPING_KEYS = %w[email name].freeze

  def sso_config_params
    permitted = params.require(:sso_configuration).permit(
      :idp_entity_id, :idp_sso_target_url, :idp_slo_target_url,
      :idp_cert, :name_identifier_format, :enforced, :enabled,
      :jit_default_role, :verified_domains_text,
      attribute_mappings: ATTRIBUTE_MAPPING_KEYS
    )
    permitted
  end
end
