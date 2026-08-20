class AppStoreReleasesController < ApplicationController
  # Note: the route helpers still reference "app_store_releases" for backward
  # compatibility, but this controller now operates on `apple_apps.cli_defaults`
  # — the legacy AppStoreRelease model has been retired. The UI label is
  # "CLI Defaults" throughout.
  #
  # URL `:id` refers to `apple_apps.id`. The `new` action takes `bundle_id_id`
  # to locate the matching AppleApp via its AppleBundleId record.

  before_action :authenticate_user!
  before_action :set_org
  before_action :set_apple_app_for_member, only: [ :show, :edit, :update, :destroy ]

  def index
    # Redirect to apps page - CLI defaults are shown on each app's show page
    redirect_to organization_apple_apps_path(@organization)
  end

  def show
    authorize @organization, :show?
  end

  def new
    authorize @organization, :manage_resources?

    scope = @organization.apple_bundle_ids
    if selected_ios_team_id.present?
      scope = scope.where("team_id = ? OR team_id IS NULL", selected_ios_team_id)
    end
    @bundle_id = scope.find(params[:bundle_id_id])
    @apple_app = @organization.apple_apps.find_by(bundle_id: @bundle_id.identifier)

    unless @apple_app
      redirect_to organization_apple_apps_path(@organization),
                  alert: "No App Store Connect app matches bundle identifier #{@bundle_id.identifier}. Sync your App Store data first."
      return
    end

    if @apple_app.cli_defaults_configured?
      redirect_to edit_organization_app_store_release_path(@organization, @apple_app),
                  alert: "CLI Defaults already exist for this app"
      return
    end

    @app_store_release = AppleApps::CliDefaultsForm.from_apple_app(
      @apple_app,
      defaults: { apple_bundle_id_id: @bundle_id.id, release_type: "AFTER_APPROVAL" }
    )
    @store_listing = @apple_app.store_listings.find_by(locale: @apple_app.primary_locale) ||
                     @apple_app.store_listings.first
  end

  def create
    authorize @organization, :manage_resources?

    scope = @organization.apple_bundle_ids
    if selected_ios_team_id.present?
      scope = scope.where("team_id = ? OR team_id IS NULL", selected_ios_team_id)
    end
    @bundle_id = scope.find(params[:app_store_release][:apple_bundle_id_id])
    @apple_app = @organization.apple_apps.find_by(bundle_id: @bundle_id.identifier)

    unless @apple_app
      redirect_to organization_apple_apps_path(@organization),
                  alert: "No App Store Connect app matches bundle identifier #{@bundle_id.identifier}."
      return
    end

    if @apple_app.update_cli_defaults(app_store_release_params)
      @apple_app.sync_content_fields_to_store_listing(content_params)
      redirect_to redirect_target_after_save,
                  notice: "CLI Defaults saved successfully"
    else
      @app_store_release = AppleApps::CliDefaultsForm
                             .from_apple_app(@apple_app, defaults: app_store_release_params.to_h)
                             .copy_errors_from(@apple_app)
      @app_store_release.apple_bundle_id_id = @bundle_id.id
      @store_listing = @apple_app.store_listings.find_by(locale: @apple_app.primary_locale) ||
                       @apple_app.store_listings.first
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @organization, :manage_resources?
    @bundle_id = @apple_app.apple_bundle_id_record
    @app_store_release = AppleApps::CliDefaultsForm.from_apple_app(@apple_app)
    @store_listing = @apple_app.store_listings.find_by(locale: @apple_app.primary_locale) ||
                     @apple_app.store_listings.first
  end

  def update
    authorize @organization, :manage_resources?
    @bundle_id = @apple_app.apple_bundle_id_record

    if @apple_app.update_cli_defaults(app_store_release_params)
      @apple_app.sync_content_fields_to_store_listing(content_params)
      redirect_to redirect_target_after_save,
                  notice: "CLI Defaults updated successfully"
    else
      @app_store_release = AppleApps::CliDefaultsForm
                             .from_apple_app(@apple_app, defaults: app_store_release_params.to_h)
                             .copy_errors_from(@apple_app)
      @store_listing = @apple_app.store_listings.find_by(locale: @apple_app.primary_locale) ||
                       @apple_app.store_listings.first
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @organization, :manage_resources?

    @apple_app.update_columns(cli_defaults: {})
    redirect_to organization_apple_app_path(@organization, @apple_app),
                notice: "CLI Defaults cleared successfully"
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  # Member actions: `:id` is an apple_apps.id.
  def set_apple_app_for_member
    @apple_app = @organization.apple_apps.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to organization_apple_apps_path(@organization),
                alert: "App not found"
  end

  def app_store_release_params
    params.require(:app_store_release).permit(
      :auto_submit,
      :phased_release,
      :version_string,
      :build_number,
      :release_type,
      :earliest_release_date
    )
  end

  def content_params
    return {} unless params[:app_store_release].is_a?(ActionController::Parameters)
    params.require(:app_store_release).permit(
      :whats_new,
      :promotional_text,
      :support_url,
      :marketing_url,
      :privacy_policy_url
    )
  end

  def redirect_target_after_save
    organization_apple_app_path(@organization, @apple_app)
  end
end
