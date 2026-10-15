class OrganizationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization, only: [ :show, :switch, :sync, :sync_google_play, :sync_status, :sync_status_google_play, :sync_all, :sync_status_all, :edit, :update, :destroy ]

  def index
    @q = params[:q].to_s.strip
    base_scope = policy_scope(Organization).includes(:owner)
    @has_organizations = base_scope.exists?
    @organizations = base_scope.search(@q)
    @organizations = @organizations.order(Arel.sql("LOWER(organizations.name) ASC")) if @q.present?
    @organization ||= Organization.new(owner: current_user)
    set_organization_create_gate_state
  end

  def new
    redirect_to organizations_path
  end

  def create
    @organization = Organization.new(organization_params.merge(owner: current_user))
    authorize @organization

    created = false
    current_user.with_lock do
      # Retry once on slug collisions caused by concurrent creates (two
      # users making "Acme" at the same moment both land on slug "acme").
      created = @organization.save_with_slug_retry
    end

    if created
      Audit::Logger.log(
        action: "organization_created",
        resource: @organization,
        metadata: { name: @organization.name },
        organization: @organization,
        request: request
      )
      redirect_to @organization, notice: "Organization created"
    else
      return if render_quota_exhausted_json_for(@organization)

      attach_quota_upgrade_guidance!(@organization)
      store_quota_upgrade_prompt!(@organization, now: true)
      # Re-fetch organizations for index view
      @q = params[:q].to_s.strip
      base_scope = policy_scope(Organization).includes(:owner)
      @has_organizations = base_scope.exists?
      @organizations = base_scope.search(@q)
      set_organization_create_gate_state(@organization)
      render :index, status: :unprocessable_content
    end
  end

  def show
    authorize @organization
    @membership = @organization.memberships.new
    @invitation = OrganizationInvitation.new
    @pending_invitations = @organization.organization_invitations.active
    @invite_member_gate = build_invite_member_gate_state if policy(@organization).invite_members?
    # Auto select current organization when viewing it
    set_current_organization!(@organization)
    @sync_running = sync_lock_present?(@organization.id)

    # Clear team filter if the selected team no longer has credentials
    if selected_ios_team_id.present?
      valid_team_ids = @organization.app_store_connect_credentials.where.not(team_id: nil).pluck(:team_id)
      unless valid_team_ids.include?(selected_ios_team_id)
        session.delete(:ios_team_id)
        @selected_ios_team_id = nil
      end
    end

    load_show_hub_data
  end

  def edit
    authorize @organization
  end

  def update
    authorize @organization
    if @organization.update(organization_params)
      Audit::Logger.log(
        action: "organization_updated",
        resource: @organization,
        metadata: { name: @organization.name },
        organization: @organization,
        request: request
      )
      redirect_to @organization, notice: "Organization updated"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @organization
    org_name = @organization.name
    org_for_audit = @organization
    # Write the audit event inside the same transaction as the destroy so a
    # rollback removes both. The audit row is inserted while the org still
    # exists (FK happy) and then re-pointed to NULL by the ON DELETE NULLIFY
    # foreign key once the org is deleted. Logging after destroy the way the
    # old code did meant the event landed on an already-deleted org and was
    # rejected by the FK, leaving no trail for the most destructive action.
    destroyed = false
    ActiveRecord::Base.transaction do
      Audit::Logger.log(
        action: "organization_deleted",
        metadata: { name: org_name, organization_id: org_for_audit.id },
        organization: org_for_audit,
        request: request
      )
      destroyed = @organization.destroy
      raise ActiveRecord::Rollback unless destroyed
    end
    redirect_to organizations_path, notice: destroyed ? "Organization deleted" : "Unable to delete organization"
  end

  def switch
    authorize @organization, :switch?
    set_current_organization!(@organization)
    redirect_to authenticated_root_path, notice: "Switched to #{@organization.name}"
  end

  def sync
    authorize @organization, :sync?
    force = ActiveModel::Type::Boolean.new.cast(params[:force])
    result = enqueue_app_store_connect_sync(@organization, force: force, min_interval: AutoSync::SYNC_MANUAL_MIN_INTERVAL)

    case result
    when :enqueued
      redirect_to @organization, notice: "App Store Connect sync enqueued"
    when :running
      redirect_to @organization, notice: "App Store Connect sync is already running"
    when :fresh
      redirect_to @organization, notice: "App Store Connect was synced recently. Use force to sync again."
    when :cooldown
      redirect_to @organization, notice: "App Store Connect sync was just queued. Please wait a moment."
    else
      redirect_to @organization, alert: "No active App Store Connect credential found"
    end
  end

  def sync_google_play
    authorize @organization, :sync?
    force = ActiveModel::Type::Boolean.new.cast(params[:force])
    result = enqueue_google_play_sync(@organization, force: force, min_interval: AutoSync::SYNC_MANUAL_MIN_INTERVAL)
    # Keep callers on this application. Rails' url_from rejects absolute and
    # protocol-relative URLs, preventing an attacker-controlled redirect_to
    # parameter from turning this endpoint into an open redirect.
    redirect_path = url_from(params[:redirect_to]) || organization_path(@organization)

    case result
    when :enqueued
      redirect_to redirect_path, notice: "Google Play sync enqueued"
    when :running
      redirect_to redirect_path, notice: "Google Play sync is already running"
    when :fresh
      redirect_to redirect_path, notice: "Google Play was synced recently. Use force to sync again."
    when :cooldown
      redirect_to redirect_path, notice: "Google Play sync was just queued. Please wait a moment."
    else
      redirect_to redirect_path, alert: "No active Google Play credential found"
    end
  end

  def sync_status
    authorize @organization, :sync?
    running = sync_lock_present?(@organization.id)
    cred = @organization.app_store_connect_credentials.order(last_synced_at: :desc).first
    render json: {
      running: running,
      last_synced_at: cred&.last_synced_at,
      last_sync_status: cred&.last_sync_status,
      last_sync_error: cred&.last_sync_error
    }
  end

  def sync_status_google_play
    authorize @organization, :sync?
    running = gp_sync_lock_present?(@organization.id)
    cred = @organization.google_play_credentials.order(last_synced_at: :desc).first
    render json: {
      running: running,
      last_synced_at: cred&.last_synced_at,
      last_sync_status: cred&.last_sync_status,
      last_sync_error: cred&.last_sync_error
    }
  end

  def sync_all
    authorize @organization, :sync?
    force = ActiveModel::Type::Boolean.new.cast(params[:force])
    dispatched = Sync::OrchestratorDispatcher.new(organization: @organization, force: force).call

    Audit::Logger.log(
      action: "sync_all_triggered",
      organization: @organization,
      actor: current_user,
      metadata: { dispatched: dispatched.transform_values(&:to_s) },
      request: request
    )

    render json: { dispatched: dispatched }, status: :accepted
  end

  def sync_status_all
    authorize @organization, :sync?
    render json: Sync::StatusAggregator.new(organization: @organization).payload
  end

  private

  def set_organization
    # Scope the lookup to orgs the current user belongs to so non-member
    # access returns 404, the same response as a non-existent id. Previously
    # Organization.find succeeded for any existing id and Pundit raised
    # NotAuthorizedError, which user_not_authorized handled via redirect_back
    # — giving attackers an enumeration oracle (302 = org exists but you're
    # not in it; 404 = doesn't exist). Organization#ensure_owner_membership!
    # guarantees owners are also members, so this still covers every legit
    # caller (Pundit policies still enforce role within the org).
    @organization = current_user.organizations.find(params[:id])
  end

  def organization_params
    params.require(:organization).permit(:name, brand_settings: [
      :primary_color, :secondary_color, :background_color, :text_color,
      :heading_font, :body_font
    ])
  end

  def set_organization_create_gate_state(record = nil)
    probe = record || Organization.new(owner: current_user, name: gate_probe_name("organization"))
    @organization_create_gate = quota_gate_state(
      probe,
      source: "organizations#index:create-organization",
      close_nearest_dialog: @organizations.any?
    )
  end

  def build_invite_member_gate_state
    probe = @organization.organization_invitations.new(
      inviter: current_user,
      email: "upgrade-probe@example.com",
      role: :viewer
    )

    quota_gate_state(
      probe,
      source: "organizations#show:invite-member",
      close_nearest_dialog: true
    )
  end

  def gate_probe_name(prefix)
    "__#{prefix}_upgrade_gate_#{SecureRandom.hex(6)}__"
  end

  # Aggregates the data the hub layout renders: stats strip counts, usage
  # bars, and the Security & Integrations summary tiles. Kept in one place
  # so the view stays declarative.
  def load_show_hub_data
    ent = @organization.entitlements

    @ios_creds_count = @organization.app_store_connect_credentials.count
    @android_creds_count = @organization.google_play_credentials.count
    @ios_apps_count = @organization.apple_apps.count
    @android_apps_count = @organization.android_apps.count

    screenshot_projects_current = @organization.screenshot_projects.count
    media_storage_current = ScreenshotProject.org_media_storage_bytes(@organization.id)

    @usage_stats = {
      seats: {
        current: @organization.seat_usage_count,
        limit:   @organization.seat_limit
      },
      screenshot_projects: {
        current: screenshot_projects_current,
        limit:   ent.max_screenshot_projects_per_organization
      },
      media_storage: {
        current: media_storage_current,
        limit:   ent.max_media_storage_bytes_per_organization
      }
    }

    @sso_configuration_present = @organization.sso_configuration.present?
    @sso_enabled_for_tier = ent.sso_enabled?
    @api_tokens_count = @organization.api_tokens.count
    @last_audit_event_at = @organization.audit_events.maximum(:created_at)
    @audit_log_enabled_for_tier = ent.audit_log_enabled?

    owner = @organization.owner
    @trial_days_remaining = owner&.on_active_trial? ? owner.trial_days_remaining : nil
    @owner_billing_subscription = owner&.current_billing_subscription
  end
end
