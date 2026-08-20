class AppStoreConnectCredentialsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_credential, only: [ :destroy, :test ]
  before_action :set_credential_for_activate, only: [ :activate ]

  def create
    is_first_credential = !@org.app_store_connect_credentials.exists?
    @credential = @org.app_store_connect_credentials.new(credential_params)
    authorize @credential

    # Validate with Apple and extract team_id
    begin
      validator = AppStoreConnect::CredentialValidator.new(
        key_id: @credential.key_id,
        issuer_id: @credential.issuer_id,
        private_key: @credential.private_key
      )

      validation = validator.validate!
      @credential.team_id = validation.team_id

      # Auto-activate if first credential
      @credential.active = is_first_credential

      if @credential.save
        # If first credential, ensure it's exclusively active
        @credential.activate_exclusively! if is_first_credential
        Audit::Logger.log(
          action: "asc_credential_added",
          resource: @credential,
          metadata: { name: @credential.name, team_id: @credential.team_id, key_id: @credential.key_id },
          organization: @org,
          request: request
        )
        sync_enqueued = trigger_initial_sync_if_needed
        redirect_to after_credential_path, notice: app_store_connect_credential_notice(created: true, sync_enqueued: sync_enqueued)
      else
        redirect_to after_credential_path, alert: @credential.errors.full_messages.to_sentence
      end
    rescue AppStoreConnect::CredentialValidator::ValidationError => e
      Audit::Logger.log(
        action: "asc_credential_validation_failed",
        metadata: {
          # Last 4 chars of the key_id only — enough to identify the key in a
          # multi-attempt diagnosis without echoing the full identifier into
          # the audit_events table.
          key_id_suffix: @credential&.key_id.to_s[-4..],
          # Structured trace from the validator: which endpoints we tried,
          # what HTTP status came back, whether `data: []` or `data: [...]`,
          # and the error class if any. Sanitized inside the validator.
          trace: Array(e.trace).map { |probe|
            {
              endpoint: probe.endpoint,
              outcome: probe.outcome.to_s,
              status: probe.status,
              data_count: probe.data_count,
              error_class: probe.error_class,
              error_message: probe.error_message
            }.compact
          }
        },
        organization: @org,
        request: request
      )
      redirect_to after_credential_path, alert: "Apple validation failed: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def destroy
    authorize @credential
    @credential.destroy
    Audit::Logger.log(
      action: "asc_credential_removed",
      metadata: { name: @credential.name },
      organization: @org,
      request: request
    )
    redirect_to @org, notice: "Credential removed"
  end

  def test
    authorize @credential, :test?
    begin
      client = AppStoreConnect::Client.new(credential: @credential)
      client.get("/v1/certificates", params: { limit: 1 })
      redirect_to @org, notice: "Connection successful"
    rescue => e
      redirect_to @org, alert: "Test failed: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def activate
    authorize @credential, :activate?
    @credential.activate_exclusively!
    Audit::Logger.log(
      action: "asc_credential_activated",
      resource: @credential,
      metadata: { name: @credential.name },
      organization: @org,
      request: request
    )
    sync_enqueued = trigger_initial_sync_if_needed
    redirect_to @org, notice: app_store_connect_credential_notice(created: false, sync_enqueued: sync_enqueued)
  end

  private

  def set_org
    # Scope to orgs the current user is a member of so unauthorized lookups
    # 404 like non-existent ids do. `Organization.find` succeeded for any id
    # and Pundit raised, which `user_not_authorized` rescued via redirect_back
    # — that 302 vs. 404 split was an enumeration oracle. Mirrors
    # OrganizationsController#set_organization. Pundit policies still enforce
    # role-within-the-org for callers that ARE members.
    @org = current_user.organizations.find(params[:organization_id])
  end

  def set_credential
    @credential = @org.app_store_connect_credentials.find(params[:id])
  end

  def set_credential_for_activate
    @credential = @org.app_store_connect_credentials.find(params[:id])
  end

  def credential_params
    params.require(:app_store_connect_credential).permit(:name, :key_id, :issuer_id, :private_key, :team_id)
  end

  def after_credential_path
    return @org unless current_user
    return onboarding_path(step: "connect") if !current_user.onboarding_completed?
    # Edge case: user clicked "Skip credential setup" earlier, which set
    # onboarding_completed_at, but has now come back to actually wire up the
    # platforms they said they ship to. Keep them on the connect step until
    # every selected platform has an active credential -- otherwise they get
    # bounced to the org dashboard right after submitting iOS, which feels
    # like the wizard ate their progress.
    return onboarding_path(step: "connect") if current_user.onboarding_has_pending_platform?(@org)
    @org
  end

  def trigger_initial_sync_if_needed
    return false unless @credential.active?
    return false unless policy(@org).sync?
    return false unless @org.scheduled_sync_enabled?

    AppStoreConnectSyncJob.perform_later(@org.id)
    true
  rescue => e
    Rails.logger.error("Failed to enqueue initial ASC sync for org #{@org.id}: #{e.message}")
    false
  end

  def app_store_connect_credential_notice(created:, sync_enqueued:)
    if created
      return "Credential added and validated successfully. Team ID: #{@credential.team_id}. Syncing..." if sync_enqueued

      return "Credential added and validated successfully. Team ID: #{@credential.team_id}"
    end

    return "Credential set active. Syncing..." if sync_enqueued

    "Credential set active"
  end
end
