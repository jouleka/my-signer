class GooglePlayCredentialsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_credential, only: [ :destroy, :test, :activate ]

  def create
    is_first_credential = !@org.google_play_credentials.exists?
    @credential = @org.google_play_credentials.new(credential_params)
    authorize @credential

    # Auto-activate if first credential
    @credential.active = is_first_credential if is_first_credential

    if @credential.save
      # If this is the first credential, make it active
      # If there are others and this one is active, deactivate the others
      @credential.activate_exclusively! if @credential.active?
      Audit::Logger.log(
        action: "google_play_credential_added",
        resource: @credential,
        metadata: { name: @credential.name },
        organization: @org,
        request: request
      )
      sync_enqueued = trigger_initial_sync_if_needed
      redirect_to after_credential_path, notice: google_play_credential_notice(created: true, sync_enqueued: sync_enqueued)
    else
      redirect_to after_credential_path, alert: @credential.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @credential
    @credential.destroy
    Audit::Logger.log(
      action: "google_play_credential_removed",
      metadata: { name: @credential.name },
      organization: @org,
      request: request
    )
    redirect_to @org, notice: "Google Play credential removed"
  end

  def test
    authorize @credential, :test?
    begin
      client = GooglePlay::Client.new(credential: @credential)
      client.ping!
      redirect_to @org, notice: "Google Play connection successful"
    rescue => e
      redirect_to @org, alert: "Google Play test failed: #{ErrorMessageSanitizer.sanitize(e)}"
    end
  end

  def activate
    authorize @credential, :activate?
    @credential.activate_exclusively!
    Audit::Logger.log(
      action: "google_play_credential_activated",
      resource: @credential,
      metadata: { name: @credential.name },
      organization: @org,
      request: request
    )
    sync_enqueued = trigger_initial_sync_if_needed
    redirect_to @org, notice: google_play_credential_notice(created: false, sync_enqueued: sync_enqueued)
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
    @credential = @org.google_play_credentials.find(params[:id])
  end

  def credential_params
    params.require(:google_play_credential).permit(:name, :service_account_json, :developer_account_id)
  end

  def after_credential_path
    return @org unless current_user
    return onboarding_path(step: "connect") if !current_user.onboarding_completed?
    # Same intent as the matching method on AppStoreConnectCredentialsController:
    # if the user prematurely finished the wizard but their onboarding_platform
    # still has at least one platform without active credentials, route them
    # back to the connect step so they can finish wiring it up.
    return onboarding_path(step: "connect") if current_user.onboarding_has_pending_platform?(@org)
    @org
  end

  def trigger_initial_sync_if_needed
    return false unless @credential.active?
    return false unless policy(@org).sync?
    return false unless @org.scheduled_sync_enabled?

    GooglePlaySyncJob.perform_later(@org.id)
    true
  rescue => e
    Rails.logger.error("Failed to enqueue initial Google Play sync for org #{@org.id}: #{e.message}")
    false
  end

  def google_play_credential_notice(created:, sync_enqueued:)
    if created
      return "Google Play credential added. Syncing..." if sync_enqueued

      return "Google Play credential added."
    end

    return "Google Play credential set active. Syncing..." if sync_enqueued

    "Google Play credential set active"
  end
end
