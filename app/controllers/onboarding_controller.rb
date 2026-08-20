class OnboardingController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_completed, except: :complete

  STEPS = %w[organization cli token connect complete].freeze
  STEP_NUMBERS = STEPS.each_with_index.to_h.freeze

  def show
    @step = resolve_step
    @step_number = STEP_NUMBERS[@step]
    @total_steps = STEPS.size - 1 # exclude "complete"

    case @step
    when "organization"
      if (existing = editable_owned_organization)
        @organization = existing
        @editing_organization = true
      else
        @organization = Organization.new(owner: current_user)
        set_organization_create_gate_state
      end
    when "cli"
      ensure_organization!
    when "token"
      ensure_organization!
      @api_token = current_organization.api_tokens.new
      dummy_token = current_organization.api_tokens.build(user: current_user)
      @can_create_admin_scope = Pundit.policy!(current_user, dummy_token).can_use_scope?("admin")
    when "connect"
      ensure_organization!
      @platform = current_user.onboarding_platform || "ios"
      @has_ios_creds = current_organization.app_store_connect_credentials.active.exists?
      @has_android_creds = current_organization.google_play_credentials.active.exists?
    when "complete"
      ensure_organization!
      complete_onboarding!
    end

    render @step
  end

  def create_organization
    @organization = Organization.new(organization_params.merge(owner: current_user))
    authorize @organization, :create?

    created = false
    current_user.with_lock do
      # Retry slug collisions caused by concurrent org creation.
      created = @organization.save_with_slug_retry
    end

    if created
      set_current_organization!(@organization)
      # Save platform preference
      platform = params[:platform].presence || "both"
      current_user.update_columns(onboarding_step: STEP_NUMBERS["cli"], onboarding_platform: platform)
      redirect_to onboarding_path(step: "cli")
    else
      attach_quota_upgrade_guidance!(@organization)
      set_organization_create_gate_state(@organization)
      @step = "organization"
      @step_number = STEP_NUMBERS[@step]
      @total_steps = STEPS.size - 1
      render :organization, status: :unprocessable_content
    end
  end

  def update_organization
    @organization = editable_owned_organization
    if @organization.nil?
      redirect_to onboarding_path(step: "organization") and return
    end

    authorize @organization, :update?

    if @organization.update(organization_params)
      platform = params[:platform].presence || current_user.onboarding_platform || "both"
      next_step_index = [ current_user.onboarding_step.to_i, STEP_NUMBERS["cli"] ].max
      current_user.update_columns(onboarding_step: next_step_index, onboarding_platform: platform)
      redirect_to onboarding_path(step: STEPS[next_step_index])
    else
      @editing_organization = true
      @step = "organization"
      @step_number = STEP_NUMBERS[@step]
      @total_steps = STEPS.size - 1
      render :organization, status: :unprocessable_content
    end
  end

  def create_token
    ensure_organization!
    org = current_organization

    permitted = params.require(:api_token).permit(:name, :scope_level)
    scope_level = permitted[:scope_level].presence || "admin"

    scopes = case scope_level
    when "admin" then %w[read write admin]
    when "write" then %w[read write]
    else %w[read]
    end

    @api_token, @plain_token = ApiToken.generate_for(
      user: current_user,
      organization: org,
      name: permitted[:name].presence || "CLI Token (Onboarding)",
      scopes: scopes,
      expires_in: nil # never expires for onboarding token
    )

    ApiTokenCreatedNotificationJob.perform_later(
      organization_id: org.id,
      creator_id: current_user.id,
      token_name: @api_token.name
    )

    current_user.update_columns(onboarding_step: STEP_NUMBERS["connect"])

    @step = "token_created"
    @step_number = STEP_NUMBERS["token"]
    @total_steps = STEPS.size - 1
    render :token_created
  end

  def advance
    step = params[:step]
    target_index = STEP_NUMBERS[step]
    return redirect_to onboarding_path if target_index.blank?

    # Only advance the persisted step forward. The rail also dispatches this
    # action for *backward* jumps (e.g. clicking the previous chapter to edit
    # an earlier answer); writing the lower index there would lose progress
    # and, since application_controller#ensure_current_user_plan_access! treats
    # `onboarding_step == 0` as "predates onboarding, auto-complete", could
    # silently mark the user complete on their next non-onboarding request.
    if target_index > current_user.onboarding_step.to_i
      current_user.update_columns(onboarding_step: target_index)
    end
    redirect_to onboarding_path(step: step)
  end

  def skip
    complete_onboarding!
    redirect_to authenticated_root_path, notice: "Welcome to MySigner! You can finish setup any time from the dashboard."
  end

  def complete
    redirect_to authenticated_root_path
  end

  private

  def resolve_step
    requested = params[:step]
    return requested if requested.present? && STEPS.include?(requested)

    # Determine step based on user state
    if current_user.organizations.none?
      "organization"
    elsif current_organization.nil?
      "organization"
    else
      current_step_index = current_user.onboarding_step
      STEPS[current_step_index] || "organization"
    end
  end

  def ensure_organization!
    return if current_organization.present?

    redirect_to onboarding_path(step: "organization"), alert: "Please create an organization first."
  end

  def complete_onboarding!
    current_user.update_columns(
      onboarding_completed_at: Time.current,
      onboarding_step: STEP_NUMBERS["complete"]
    )
  end

  def redirect_if_completed
    return unless current_user.onboarding_completed_at.present?

    # Pair with the credential controllers' after_credential_path: if the user
    # finished the wizard early but is now back to add a credential they
    # skipped, let them view the connect step instead of bouncing them to the
    # dashboard. We're explicit about the action+step so this only loosens the
    # gate for the resume-credentials flow, not for /onboarding generally.
    if action_name == "show" && params[:step] == "connect" &&
        current_user.onboarding_has_pending_platform?(current_organization)
      return
    end

    redirect_to authenticated_root_path
  end

  def organization_params
    params.require(:organization).permit(:name)
  end

  # Returns the org the current user owns and is allowed to update from the
  # onboarding wizard, or nil if they don't own one. We only treat the
  # currently-selected org as editable here -- if a user is a member of someone
  # else's org but owns none of their own, we still want to show the create
  # form so they can spin up their own workspace.
  def editable_owned_organization
    return nil unless current_organization
    return nil unless current_organization.owner_id == current_user.id
    current_organization
  end

  def set_organization_create_gate_state(record = nil)
    probe = record || Organization.new(owner: current_user, name: "__onboarding_probe_#{SecureRandom.hex(6)}__")
    @organization_create_gate = quota_gate_state(
      probe,
      source: "onboarding#create_organization"
    )
  end
end
