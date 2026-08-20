class ApiTokensController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_token, only: [ :destroy ]

  def index
    authorize @organization, :manage_api_tokens?
    @api_tokens = @organization.api_tokens.includes(:user).order(created_at: :desc)

    # Pre-build for the inline new token modal
    @api_token = @organization.api_tokens.new
    dummy_token = @organization.api_tokens.build(user: current_user)
    @can_create_admin_scope = Pundit.policy!(current_user, dummy_token).can_use_scope?("admin")
  end

  def new
    authorize @organization, :manage_api_tokens?
    @api_token = @organization.api_tokens.new

    # Check if user can create admin scope tokens
    dummy_token = @organization.api_tokens.build(user: current_user)
    @can_create_admin_scope = Pundit.policy!(current_user, dummy_token).can_use_scope?("admin")
  end

  def create
    authorize @organization, :manage_api_tokens?

    permitted = params.require(:api_token).permit(:name, :expires_in, :scope_level)
    scope_level = permitted[:scope_level].presence || "read"

    # Check if user can use the requested scope level
    dummy_token = @organization.api_tokens.build(user: current_user)
    @can_create_admin_scope = Pundit.policy!(current_user, dummy_token).can_use_scope?("admin")

    unless Pundit.policy!(current_user, dummy_token).can_use_scope?(scope_level)
      @api_token = @organization.api_tokens.build(name: permitted[:name])
      @api_token.errors.add(:base, "You don't have permission to create tokens with '#{scope_level}' scope")
      render :new, status: :unprocessable_content
      return
    end

    # Expand scope level to include all necessary scopes
    scopes = case scope_level
    when "admin"
      [ "read", "write", "admin" ]
    when "write"
      [ "read", "write" ]
    else
      [ "read" ]
    end

    expires_in = case permitted[:expires_in]
    when "30_days" then 30.days
    when "90_days" then 90.days
    when "1_year" then 1.year
    when "never" then nil
    else 90.days
    end

    # Build token first to validate
    @api_token = @organization.api_tokens.build(
      user: current_user,
      name: permitted[:name],
      scopes: scopes.join(","),
      expires_at: expires_in ? expires_in.from_now : nil,
      token_digest: "temp" # temp value for validation
    )

    if @api_token.valid?
      # Generate actual token
      @api_token, @plain_token = ApiToken.generate_for(
        user: current_user,
        organization: @organization,
        name: permitted[:name],
        scopes: scopes,
        expires_in: expires_in
      )

      Audit::Logger.log(
        action: "api_token_created",
        resource: @api_token,
        metadata: { name: @api_token.name, scopes: @api_token.scopes },
        organization: @organization,
        request: request
      )

      ApiTokenCreatedNotificationJob.perform_later(
        organization_id: @organization.id,
        creator_id: current_user.id,
        token_name: permitted[:name]
      )

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("api_token_modal", partial: "api_tokens/created") }
        format.html do
          flash[:api_token] = @plain_token
          redirect_to organization_api_tokens_path(@organization), notice: "API token created successfully. Copy it now, you won't see it again!"
        end
      end
    else
      render :new, status: :unprocessable_content
    end
  rescue => e
    @api_token ||= @organization.api_tokens.build(name: permitted[:name])
    @can_create_admin_scope ||= Pundit.policy!(current_user, @organization.api_tokens.build(user: current_user)).can_use_scope?("admin")
    @api_token.errors.add(:base, e.message)
    render :new, status: :unprocessable_content
  end

  def destroy
    authorize @token
    token_name = @token.name
    @token.revoke!
    Audit::Logger.log(
      action: "api_token_revoked",
      resource: @token,
      metadata: { name: token_name },
      organization: @organization,
      request: request
    )

    ApiTokenRevokedNotificationJob.perform_later(
      organization_id: @organization.id,
      revoker_id: current_user.id,
      token_name: token_name
    )

    redirect_back fallback_location: organization_api_tokens_path(@organization), notice: "API token revoked"
  end

  private

  def set_organization
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_token
    @token = @organization.api_tokens.find(params[:id])
  end
end
