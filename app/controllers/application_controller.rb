class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include Pundit::Authorization
  include AutoSync

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  # BYOK revocation surfaces from deep in the credential read path
  # (CredentialVault.decrypt). Rescuing it here means every credential-touching
  # controller gets the actionable 403 + rate-limited audit for free, without
  # peppering individual controllers with rescue blocks. mysigner-21 sub-ticket 2.4.
  rescue_from CredentialVault::CustomerKeyRevoked, with: :handle_customer_key_revoked

  helper_method :current_organization, :selected_ios_team_id

  before_action :ensure_current_user_plan_access!
  before_action :redirect_to_onboarding_if_needed
  before_action :set_current_attributes

  private

  def ensure_current_user_plan_access!
    return unless user_signed_in?
    return unless Organization.access_state_supported?
    return unless current_user_plan_access_out_of_sync?

    Pricing::PlanEnforcer.new(current_user).apply!
  end

  def redirect_to_onboarding_if_needed
    return unless user_signed_in?
    return if devise_controller?
    return if self.is_a?(OnboardingController)
    return if request.path.start_with?("/api/")
    return if request.path == "/users" # sign out
    return if current_user.onboarding_completed_at.present?

    # Allow credential and org-related POST actions during onboarding
    # (the credential modals submit to these controllers from the connect step)
    if current_user.onboarding_step > 0
      return if self.is_a?(AppStoreConnectCredentialsController)
      return if self.is_a?(GooglePlayCredentialsController)
      return if self.is_a?(OrganizationsController) && action_name == "switch"
    end

    # Existing users who already have organizations and never started onboarding
    # don't need it (they predate the feature).
    if current_user.organizations.exists? && current_user.onboarding_step == 0
      current_user.update_columns(onboarding_completed_at: Time.current)
      return
    end

    redirect_to onboarding_path
  end

  def user_not_authorized
    respond_to do |format|
      format.html do
        redirect_back fallback_location: (user_signed_in? ? authenticated_root_path : unauthenticated_root_path), alert: "You are not authorized to perform this action."
      end
      format.json { render json: { error: "forbidden" }, status: :forbidden }
    end
  end

  # Surface user-actionable copy from the design doc verbatim. Locked text
  # because the customer-facing onboarding doc (sub-ticket 2.5) quotes it.
  # Don't paraphrase here without also updating that doc.
  CUSTOMER_KEY_REVOKED_MESSAGE =
    "Your CMK is unreachable. Re-grant MySigner access or clear BYOK in Settings → Security.".freeze

  def handle_customer_key_revoked(error)
    # Audit first, then respond. If audit emission fails internally (the
    # logger swallows errors), the user still gets the 403; we never let a
    # logging hiccup mask a security-relevant failure.
    emit_revocation_audit_once(current_organization, error) if current_organization

    # Format selection note: clients that don't send an explicit
    # `Accept: application/json` get the HTML branch (Rails defaults
    # request.format to :html for missing/`*/*` Accept). CLI/API callers
    # MUST send Accept: application/json to receive the locked
    # `code: "byok_key_revoked"` payload. Matches the same convention as
    # `user_not_authorized` above — keeps the codebase consistent on
    # forbidden-response shape.
    respond_to do |format|
      format.html do
        # Match the user_not_authorized pattern (redirect_back + flash). If
        # current_organization is available we'd prefer to land them on the
        # org settings page where they can clear BYOK; redirect_back covers
        # the general case (any controller can raise this) and avoids a
        # redirect loop if the offending action IS the settings page itself.
        target = current_organization ? organization_path(current_organization) : authenticated_root_path
        redirect_back fallback_location: target, alert: CUSTOMER_KEY_REVOKED_MESSAGE
      end
      format.json do
        render json: { error: CUSTOMER_KEY_REVOKED_MESSAGE, code: "byok_key_revoked" }, status: :forbidden
      end
    end
  end

  # Rate-limited audit emission for BYOK revocation detection. One event
  # per org per 5 minutes — enough for an on-call to notice without burying
  # the audit log under retry-storm noise. Cache miss (e.g. Solid Cache
  # down) falls through and emits every time; that's noisy but not broken.
  # mysigner-21 sub-ticket 2.4.
  def emit_revocation_audit_once(organization, error)
    Rails.cache.fetch("byok_revoke_warned:#{organization.id}", expires_in: 5.minutes) do
      Audit::Logger.log(
        action:       "byok_kms_key_revoked_detected",
        organization: organization,
        metadata: {
          "arn"           => organization.byok_kms_key_arn,
          # Prefer the underlying AWS error class (set as cause when
          # CredentialVault.decrypt re-raises). Falls back to the wrapper
          # class so forensics still see SOMETHING if the error wasn't
          # produced via the standard re-raise path (e.g. in a test stub).
          "error_class"   => error.cause&.class&.name || error.class.name,
          "error_message" => error.message
        }
      )
      true # cache-stored sentinel; presence (not value) suppresses re-emission
    end
  end

  def quota_exhausted_error_detail(record)
    Pricing::UpgradePromptPayload.quota_detail(record)
  end

  # Renders the shared Team-feature paywall page when a user tries to access a
  # feature that requires the Team plan. Used by AuditEventsController,
  # PermissionsController, SsoConfigurationsController. The feature hash
  # describes what they're missing so the upgrade CTA has context.
  #
  # When called from a `before_action`, it short-circuits the action chain.
  # Calls `skip_authorization` so Pundit's verify_authorized after_action is
  # satisfied even though we never invoked `authorize`.
  def render_team_feature_paywall!(name:, icon:, description:, bullets: [])
    skip_authorization if respond_to?(:skip_authorization)
    skip_policy_scope if respond_to?(:skip_policy_scope)

    # Render the shared template inside the default application layout so the
    # user keeps the navbar, sidebar, etc. The template at
    # app/views/shared/team_feature_paywall.html.erb takes a `feature:` local.
    render template: "shared/team_feature_paywall",
      status: :ok,
      locals: {
        feature: { name: name, icon: icon, description: description, bullets: bullets }
      }
  end

  def upgrade_plan_suggestion(current_plan:, required_plan:, feature:)
    Pricing::UpgradePromptPayload.plan_suggestion(
      current_plan: current_plan,
      required_plan: required_plan,
      feature: feature
    )
  end

  def upgrade_quota_suggestion(current_plan:, next_plan:, feature:)
    Pricing::UpgradePromptPayload.quota_suggestion(
      current_plan: current_plan,
      next_plan: next_plan,
      feature: feature
    )
  end

  def quota_upgrade_guidance(detail)
    Pricing::UpgradePromptPayload.quota_guidance(detail)
  end

  def quota_exhausted_message(record)
    detail = quota_exhausted_error_detail(record)
    return record.errors.full_messages.to_sentence unless detail

    "#{record.errors.full_messages.to_sentence} #{quota_upgrade_guidance(detail)}"
  end

  def attach_quota_upgrade_guidance!(record)
    detail = quota_exhausted_error_detail(record)
    return false unless detail

    suggestion = quota_upgrade_guidance(detail)
    record.errors.add(:base, suggestion) unless record.errors[:base].include?(suggestion)
    true
  end

  def render_quota_exhausted_json_for(record)
    detail = quota_exhausted_error_detail(record)
    return false unless detail && request.format.json?

    render json: {
      error: "quota_exhausted",
      message: record.errors.full_messages.to_sentence,
      current_plan: detail[:current_plan].to_s,
      next_plan: detail[:next_plan]&.to_s,
      suggestion: quota_upgrade_guidance(detail),
      timestamp: Time.current.iso8601
    }.compact, status: :unprocessable_content

    true
  end

  def plan_upgrade_prompt_payload(current_plan:, required_plan: nil, feature:, message:, suggestion:, source: nil)
    Pricing::UpgradePromptPayload.build(
      current_plan: current_plan,
      required_plan: required_plan,
      feature: feature,
      message: message,
      suggestion: suggestion,
      source: source || "#{controller_name}##{action_name}"
    )
  end

  def quota_upgrade_prompt_payload(record)
    Pricing::UpgradePromptPayload.for_quota_record(
      record,
      source: "#{controller_name}##{action_name}"
    )
  end

  def store_upgrade_prompt!(payload, now: false)
    return false if payload.blank?

    target_flash = now ? flash.now : flash
    target_flash[:upgrade_prompt] = payload.deep_stringify_keys
    true
  end

  def store_quota_upgrade_prompt!(record, now: false)
    store_upgrade_prompt!(quota_upgrade_prompt_payload(record), now: now)
  end

  def quota_gate_state(record, source:, close_nearest_dialog: false)
    gate_record = record.errors.any? ? record : record.dup
    gate_record.valid? if gate_record.errors.empty?

    prompt = Pricing::UpgradePromptPayload.for_quota_record(gate_record, source: source)
    {
      blocked: prompt.present?,
      prompt: prompt || {},
      closeNearestDialog: close_nearest_dialog
    }
  end

  def after_sign_in_path_for(resource)
    token = session.delete(:pending_invite_token)
    if token.present?
      if (invite = OrganizationInvitation.active.find_by(token: token))
        if invite.acceptance_allowed_for?(resource)
          begin
            invite.accept!(resource)
            flash[:notice] = "You've joined #{invite.organization.name}"
            return organization_path(invite.organization)
          rescue => e
            flash[:alert] = e.message
          end
        else
          flash[:alert] = "This invitation is not for your account"
        end
      end
    end
    # New users go to onboarding
    unless resource.onboarding_completed?
      return onboarding_path unless resource.organizations.exists?
    end

    # Restore last organization if nothing in session
    if resource.last_organization_id.present? && session[:current_organization_id].blank?
      if (org = Organization.find_by(id: resource.last_organization_id)) && Pundit.policy!(resource, org).show?
        session[:current_organization_id] = org.id
        sync_if_stale(org)
      end
    end
    super
  end

  # Returns the organization selected in the user's session, if any and authorized
  def current_organization
    return @current_organization if defined?(@current_organization)
    @current_organization = nil
    return nil unless user_signed_in?

    org_id = session[:current_organization_id]
    return @current_organization = restore_accessible_organization if org_id.blank?

    begin
      org = Organization.find_by(id: org_id)
      if org && Pundit.policy!(current_user, org).show?
        @current_organization = org
      else
        session.delete(:current_organization_id)
        @current_organization = restore_accessible_organization
      end
    rescue StandardError
      session.delete(:current_organization_id)
      @current_organization = restore_accessible_organization
    end

    @current_organization
  end

  # Sets the current organization in session after authorization
  def set_current_organization!(organization)
    authorize organization, :show?
    session[:current_organization_id] = organization.id
    @current_organization = organization
    Current.organization = @current_organization
    # Persist for future sessions
    if current_user && current_user.last_organization_id != organization.id
      current_user.update_column(:last_organization_id, organization.id)
    end
  end

  def set_current_attributes
    Current.user = current_user
    Current.organization = current_organization if user_signed_in?
  end

  def normalize_current_organization_context!
    return nil unless user_signed_in?

    remove_instance_variable(:@current_organization) if instance_variable_defined?(:@current_organization)
    organization = current_organization
    Current.organization = organization
    organization
  end

  # Returns the selected iOS team_id from params or session
  # Returns nil when "All Teams" is selected (no team filtering)
  def selected_ios_team_id
    return @selected_ios_team_id if defined?(@selected_ios_team_id)

    # If params explicitly checked for team_id (including nil)
    if params.key?(:team_id)
      team_id = params[:team_id].presence
      # Store or clear in session
      if team_id.present?
        session[:ios_team_id] = team_id
      else
        session.delete(:ios_team_id)
      end
      @selected_ios_team_id = team_id
    else
      # Use session if available
      @selected_ios_team_id = session[:ios_team_id]
    end

    @selected_ios_team_id
  end

  def quota_feature_name(feature)
    Pricing::UpgradePromptPayload.feature_name(feature)
  end

  def restore_accessible_organization
    preferred_org =
      if current_user.last_organization_id.present?
        Organization.find_by(id: current_user.last_organization_id)
      end

    if preferred_org && Pundit.policy!(current_user, preferred_org).show?
      session[:current_organization_id] = preferred_org.id
      return preferred_org
    end

    fallback_org = preferred_accessible_organization_for(current_user)
    session[:current_organization_id] = fallback_org&.id
    fallback_org
  end

  def preferred_accessible_organization_for(user)
    user.owned_organizations.accessible.order(:created_at, :id).first ||
      user.organizations.accessible.order("organizations.created_at ASC, organizations.id ASC").first
  end

  def current_user_plan_access_out_of_sync?
    owned_scope = current_user.owned_organizations
    limit = current_user.entitlements.max_owned_organizations
    owned_count = owned_scope.count

    return true if owned_count > limit && owned_scope.accessible.count > limit
    return true if owned_count <= limit && owned_scope.plan_blocked.exists?

    last_org_id = current_user.last_organization_id
    return false if last_org_id.blank?

    current_user.organizations.exists?(id: last_org_id) && !current_user.organizations.accessible.exists?(id: last_org_id)
  end
end
