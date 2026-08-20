class AppleAdsCredentialsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization
  before_action :set_credential
  before_action :authorize_credential!
  after_action :verify_authorized

  # GET /organizations/:organization_id/apple_ads_credential/new
  def new
    if @organization.apple_ads_credential&.persisted?
      redirect_to edit_organization_apple_ads_credential_path(@organization)
    end
  end

  # POST /organizations/:organization_id/apple_ads_credential
  def create
    if @organization.apple_ads_credential&.persisted?
      redirect_to edit_organization_apple_ads_credential_path(@organization),
                  alert: "Credential already connected. Use edit to update."
      return
    end
    @credential.assign_attributes(permitted)
    if @credential.save
      verify_connection!
      if @credential.last_successful?
        Audit::Logger.log(
          action: :apple_ads_credential_added,
          organization: @organization,
          actor: current_user,
          metadata: {},
          request: request
        )
        redirect_to organization_keywords_path(@organization), notice: "Apple Search Ads connected."
      else
        # Saved but OAuth failed — leave the record with last_error set so the
        # user can see what went wrong and retry without re-entering credentials.
        render_create_failure
      end
    else
      render_create_failure
    end
  end

  # GET /organizations/:organization_id/apple_ads_credential/edit
  def edit
  end

  # PATCH/PUT /organizations/:organization_id/apple_ads_credential
  def update
    if @credential.update(permitted)
      verify_connection!
      if @credential.last_successful?
        redirect_to organization_keywords_path(@organization), notice: "Updated."
      else
        render :edit, status: :unprocessable_content
      end
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /organizations/:organization_id/apple_ads_credential
  def destroy
    @credential.destroy
    Audit::Logger.log(
      action: :apple_ads_credential_removed,
      organization: @organization,
      actor: current_user,
      metadata: {},
      request: request
    )
    redirect_to organization_keywords_path(@organization), notice: "Disconnected."
  end

  private

  def set_organization
    # Scope to orgs the current user is a member of so unauthorized lookups
    # 404 like non-existent ids do. `Organization.find` succeeded for any id
    # and Pundit raised, which `user_not_authorized` rescued via redirect_back
    # — that 302 vs. 404 split was an enumeration oracle. Mirrors
    # OrganizationsController#set_organization. Pundit policies still enforce
    # role-within-the-org for callers that ARE members.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_credential
    @credential = @organization.apple_ads_credential || @organization.build_apple_ads_credential
  end

  def authorize_credential!
    authorize @credential
  end

  def permitted
    raw = params.require(:apple_ads_credential).permit(:client_id, :team_id, :key_id, :private_key_pem)
    raw.delete(:private_key_pem) if raw[:private_key_pem].blank?
    raw
  end

  # Shared failure renderer for #create. Turbo-driven submissions (both the
  # Connect modal AND the standalone /new page under Turbo Drive) replace the
  # shared #apple-ads-credential-errors target so the form state is preserved
  # and errors render inline. Non-Turbo HTML falls back to re-rendering :new.
  # Both paths return 422.
  def render_create_failure
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "apple-ads-credential-errors",
          partial: "apple_ads_credentials/credential_errors",
          locals: { credential: @credential }
        ), status: :unprocessable_content
      end
      format.html { render :new, status: :unprocessable_content }
    end
  end

  # Attempts an OAuth token exchange. On success, the credential is marked with
  # last_successful_at. On Aso::AppleAds::Error (including CredentialsInvalid,
  # RateLimited, TransientError), the message is persisted to last_error and
  # the caller falls through to render :new / :edit with 422.
  def verify_connection!
    Aso::AppleAds::Client.new(credential: @credential).access_token
    @credential.mark_success!
  rescue Aso::AppleAds::Error, Faraday::Error, OpenSSL::PKey::PKeyError => e
    @credential.mark_failure!(e.message)
  rescue StandardError => e
    Rails.logger.error(event: "apple_ads_verify.unexpected", class: e.class.name, message: e.message)
    @credential.mark_failure!("Connection test failed: #{e.class.name}")
  end
end
