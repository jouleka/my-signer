class AndroidReleasesController < ApplicationController
  # HTML controller for the Android CLI Defaults page — the webapp form that
  # writes `android_apps.cli_defaults`. Mirrors the iOS
  # AppStoreReleasesController pattern but simpler (no StoreListing content
  # sync — Android release notes live directly in cli_defaults.release_notes
  # keyed by BCP-47 locale).

  before_action :authenticate_user!
  before_action :set_org
  before_action :set_android_app, only: [ :edit, :update, :destroy ]

  def edit
    authorize @organization, :manage_resources?
  end

  def update
    authorize @organization, :manage_resources?

    if @android_app.update_cli_defaults(android_release_params)
      redirect_to organization_android_app_path(@organization, @android_app),
                  notice: "CLI Defaults saved for #{@android_app.name.presence || @android_app.package_name}"
    else
      flash.now[:alert] = "Could not save CLI Defaults"
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @organization, :manage_resources?
    @android_app.update!(cli_defaults: {})
    redirect_to organization_android_app_path(@organization, @android_app),
                notice: "CLI Defaults cleared for #{@android_app.name.presence || @android_app.package_name}"
  end

  private

  def set_org
    @organization = current_user.organizations.find(params[:organization_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Organization not found"
  end

  def set_android_app
    @android_app = @organization.android_apps.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to organization_android_apps_path(@organization), alert: "Android app not found"
  end

  # Accepts top-level form fields plus a free-form `release_notes` hash
  # (locale => text). `country_targeting` is deferred — the edit form keeps
  # the simplest knobs for now; power users can PATCH via the API to set it.
  def android_release_params
    permitted = params.require(:android_release).permit(
      :default_track,
      :default_status,
      :default_user_fraction,
      :default_in_app_update_priority,
      :changes_not_sent_for_review,
      :release_name
    ).to_h

    release_notes = params.dig(:android_release, :release_notes)
    if release_notes.respond_to?(:to_unsafe_h)
      permitted[:release_notes] = release_notes.to_unsafe_h
    elsif release_notes.is_a?(Hash)
      permitted[:release_notes] = release_notes
    end

    permitted
  end
end
