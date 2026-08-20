# Controller for the per-org Bring-Your-Own-Key (BYOK) panel under
# Settings → Security. Hosts the Verify, Save, and Clear endpoints.
#
# Verify (POST) runs both KMS probes against the customer's CMK ARN and
# returns JSON — it never persists. Save (PATCH with a value) runs the same
# probes; on success, persists the ARN and emits a `byok_registered` audit.
# Clear (PATCH with a blank value) wipes the column and emits `byok_cleared`.
#
# This controller follows the SsoConfigurationsController pattern:
# scoped to current_user.organizations.find (404 for non-members before
# any tier check, to avoid an enumeration oracle on the paywall page),
# Pundit-gated, and audit-logging.
#
# Re-wrap of existing envelopes on register/clear is handled by the
# Organization model's `before_save :rewrap_credentials_on_byok_change`
# callback, not here — this controller just sets the column.
#
# Companion ticket: mysigner-21.
class ByokSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  # Entitlement check runs BEFORE Pundit so non-Team (Free/Pro) orgs see the
  # friendly Team-feature paywall page on every BYOK route instead of a
  # generic Pundit denial. `set_organization` already scoped to memberships,
  # so non-members get a 404 before this paywall can echo org name/plan into
  # the DOM (matches the SsoConfigurationsController ordering).
  before_action :require_byok_entitlement!
  after_action :verify_authorized

  # POST /organizations/:organization_id/security/byok/verify
  # Runs both KMS probes against the supplied ARN. Returns JSON. Does NOT
  # save. On any probe failure, emits `byok_verify_failed`.
  def verify
    authorize @organization, :manage_byok?

    arn = params[:byok_kms_key_arn].to_s.strip
    if arn.blank?
      render json: { ok: false, error: "ARN is required." }, status: :unprocessable_content
      return
    end

    unless arn.match?(Organization::BYOK_KMS_KEY_ARN_REGEX)
      audit_verify_failed(arn, "ArgumentError", "invalid ARN format")
      render json: {
        ok: false,
        error: "ARN must be a full KMS key ARN in us-east-1 (alias and bare key IDs are not accepted)."
      }, status: :unprocessable_content
      return
    end

    result = CredentialVault::ByokVerifier.verify(organization: @organization, key_arn: arn)
    if result.ok?
      render json: { ok: true }
    else
      audit_verify_failed(arn, result.error_class, result.error_message)
      render json: { ok: false, error: result.message }, status: :unprocessable_content
    end
  end

  # PATCH /organizations/:organization_id/security/byok
  # Either sets or clears the ARN. On set: probes first, then persists, then
  # audits `byok_registered`. On clear: persists nil, then audits
  # `byok_cleared` (only if the column was previously populated — clearing
  # an already-blank value is a no-op without an audit row).
  def update
    arn = params[:byok_kms_key_arn].to_s.strip

    if arn.blank?
      # Clearing is a role-only action allowed on ANY tier — a downgraded org
      # must keep this off-ramp (see OrganizationPolicy#clear_byok?).
      authorize @organization, :clear_byok?
      clear_arn_and_audit
    else
      # Registering a new CMK requires the Team entitlement.
      authorize @organization, :manage_byok?
      register_arn_and_audit(arn)
    end
  end

  private

  def set_organization
    # Scope to memberships so a non-member request returns 404 BEFORE Pundit
    # surfaces the tier/role denial. Otherwise the response shape itself
    # leaks org existence ("forbidden" vs "not found"). Matches the
    # SsoConfigurationsController#set_org rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  # Gate BYOK behind the Team tier. Non-Team (Free/Pro) orgs get the shared
  # Team-feature paywall page with an upgrade CTA instead of a generic Pundit
  # denial. Runs after `set_organization` (so non-members already 404'd) and
  # before the per-action `authorize` calls. Mirrors
  # SsoConfigurationsController#require_sso_entitlement!.
  def require_byok_entitlement!
    return if @organization.entitlements.byok_enabled?
    # Always allow CLEARING BYOK (PATCH with a blank ARN), even for non-Team
    # orgs, so a downgraded org keeps its decryption-recovery off-ramp.
    # Registering a new CMK (non-blank) and verifying still require Team.
    return if clearing_byok_request?

    render_team_feature_paywall!(
      name: "Bring Your Own Key (BYOK)",
      icon: "fa-key",
      description: "Wrap your signing-credential DEKs with a customer-managed key (CMK) in your own AWS account, and revoke MySigner's access at any time from your AWS key policy.",
      bullets: [
        "Per-org customer-managed KMS key (CMK)",
        "Envelope encryption rooted in your AWS account",
        "Revoke MySigner access from your own key policy",
        "Automatic re-wrap of existing credential envelopes on register/clear",
        "Audit log for every BYOK register, clear, and verification"
      ]
    )
  end

  # True when this request is clearing BYOK: PATCH #update with a blank ARN.
  # Such requests bypass the Team paywall (and authorize via :clear_byok?).
  def clearing_byok_request?
    action_name == "update" && params[:byok_kms_key_arn].to_s.strip.blank?
  end

  def clear_arn_and_audit
    previous_arn = @organization.byok_kms_key_arn
    if previous_arn.blank?
      redirect_to organization_path(@organization),
                  notice: "BYOK is already cleared."
      return
    end

    @organization.update!(byok_kms_key_arn: nil)
    # `last_rewrap_counts` is populated by the org's before_save callback
    # (Organization#rewrap_credentials_on_byok_change) which ran inside the
    # update! above. `|| {}` defends against the (rare) case where the
    # callback didn't fire because the column didn't actually change —
    # shouldn't happen via this controller flow (we already early-returned
    # on blank previous_arn) but is the right default.
    Audit::Logger.log(
      action: "byok_cleared",
      actor: current_user,
      organization: @organization,
      resource: @organization,
      metadata: {
        "previous_arn"  => previous_arn,
        "rewrap_counts" => @organization.last_rewrap_counts || {}
      },
      request: request
    )
    redirect_to organization_path(@organization), notice: "BYOK CMK cleared."
  end

  def register_arn_and_audit(arn)
    unless arn.match?(Organization::BYOK_KMS_KEY_ARN_REGEX)
      audit_verify_failed(arn, "ArgumentError", "invalid ARN format")
      redirect_to organization_path(@organization),
                  alert: "ARN must be a full KMS key ARN in us-east-1 (alias and bare key IDs are not accepted)."
      return
    end

    result = CredentialVault::ByokVerifier.verify(organization: @organization, key_arn: arn)
    unless result.ok?
      audit_verify_failed(arn, result.error_class, result.error_message)
      redirect_to organization_path(@organization), alert: result.message
      return
    end

    if @organization.update(byok_kms_key_arn: arn)
      # `last_rewrap_counts` is populated by the org's before_save callback
      # (Organization#rewrap_credentials_on_byok_change) which ran inside
      # the update above. `|| {}` covers the (rare) case where the callback
      # didn't run because the column wasn't actually changed.
      Audit::Logger.log(
        action: "byok_registered",
        actor: current_user,
        organization: @organization,
        resource: @organization,
        metadata: {
          "arn"           => arn,
          "rewrap_counts" => @organization.last_rewrap_counts || {}
        },
        request: request
      )
      redirect_to organization_path(@organization), notice: "BYOK CMK saved."
    else
      redirect_to organization_path(@organization),
                  alert: @organization.errors.full_messages.to_sentence.presence ||
                         "BYOK CMK could not be saved."
    end
  end

  def audit_verify_failed(arn, error_class, error_message)
    Audit::Logger.log(
      action: "byok_verify_failed",
      actor: current_user,
      organization: @organization,
      resource: @organization,
      metadata: {
        "arn"           => arn,
        "error_class"   => error_class.to_s,
        "error_message" => error_message.to_s
      },
      request: request
    )
  end
end
