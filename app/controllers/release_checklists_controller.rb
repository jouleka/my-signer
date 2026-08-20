class ReleaseChecklistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :set_checklist
  before_action :require_release_checklist_write!, only: %i[update check_item uncheck_item reset add_custom_item remove_custom_item]
  after_action :verify_authorized

  # GET /organizations/:organization_id/releases/:release_id/release_checklists/:id
  def show
    authorize @checklist

    respond_to do |format|
      format.html
      format.json do
        render json: {
          id: @checklist.id,
          version_string: @checklist.version_string,
          platform: @checklist.platform,
          items: @checklist.items,
          custom_items: @checklist.custom_items,
          completion: @checklist.completion_percentage,
          ready: @checklist.ready_for_submission?
        }
      end
    end
  end

  # PATCH /organizations/:organization_id/releases/:release_id/release_checklists/:id
  def update
    authorize @checklist

    if @checklist.update(checklist_params)
      respond_to do |format|
        format.html { redirect_to organization_release_path(@organization, params[:release_id]), notice: "Checklist updated." }
        format.json { render json: { status: "updated", completion: @checklist.completion_percentage } }
      end
    else
      respond_to do |format|
        format.html { render :show, status: :unprocessable_content }
        format.json { render json: { errors: @checklist.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  # POST /organizations/:organization_id/releases/:release_id/release_checklists/:id/check_item
  def check_item
    authorize @checklist, :check_item?

    @checklist.check_item!(params[:key], current_user)

    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace("release-checklist", partial: "releases/checklist", locals: {
          checklist: @checklist.reload, app: find_release_app
        })
      }
      format.json { render json: { status: "checked", completion: @checklist.completion_percentage, ready: @checklist.ready_for_submission? } }
    end
  end

  # POST /organizations/:organization_id/releases/:release_id/release_checklists/:id/uncheck_item
  def uncheck_item
    authorize @checklist, :uncheck_item?

    @checklist.uncheck_item!(params[:key])

    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace("release-checklist", partial: "releases/checklist", locals: {
          checklist: @checklist.reload, app: find_release_app
        })
      }
      format.json { render json: { status: "unchecked", completion: @checklist.completion_percentage, ready: @checklist.ready_for_submission? } }
    end
  end

  # POST /organizations/:organization_id/releases/:release_id/release_checklists/:id/reset
  def reset
    authorize @checklist, :reset?

    @checklist.items.each { |item| item["checked"] = false; item["checked_by_id"] = nil; item["checked_at"] = nil }
    @checklist.save!

    redirect_to organization_release_path(@organization, params[:release_id]), notice: "Checklist has been reset."
  end

  # POST /organizations/:organization_id/releases/:release_id/release_checklists/:id/add_custom_item
  def add_custom_item
    authorize @checklist, :update?

    label = params[:label].to_s.strip
    required = ActiveModel::Type::Boolean.new.cast(params[:required])

    if @checklist.add_custom_item!(label: label, required: required, user: current_user)
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace("release-checklist", partial: "releases/checklist", locals: {
            checklist: @checklist.reload, app: find_release_app
          })
        }
        format.json { render json: { custom_items: @checklist.custom_items, completion_percentage: @checklist.completion_percentage } }
        format.html { redirect_back fallback_location: organization_release_path(@organization, params[:release_id]), notice: "Custom item added." }
      end
    else
      respond_to do |format|
        format.json { render json: { error: "Could not add item (blank or duplicate)" }, status: :unprocessable_content }
        format.html { redirect_back fallback_location: organization_releases_path(@organization), alert: "Could not add checklist item." }
      end
    end
  end

  # DELETE /organizations/:organization_id/releases/:release_id/release_checklists/:id/remove_custom_item
  def remove_custom_item
    authorize @checklist, :update?

    key = params[:key].to_s
    if @checklist.remove_custom_item!(key)
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace("release-checklist", partial: "releases/checklist", locals: {
            checklist: @checklist.reload, app: find_release_app
          })
        }
        format.json { render json: { custom_items: @checklist.custom_items, completion_percentage: @checklist.completion_percentage } }
        format.html { redirect_back fallback_location: organization_release_path(@organization, params[:release_id]), notice: "Custom item removed." }
      end
    else
      respond_to do |format|
        format.json { render json: { error: "Item not found" }, status: :not_found }
        format.html { redirect_back fallback_location: organization_releases_path(@organization), alert: "Item not found." }
      end
    end
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def set_checklist
    @checklist = @organization.release_checklists.find(params[:id])
  end

  def require_release_checklist_write!
    return unless @organization.entitlements.release_checklist_read_only?

    respond_to do |format|
      format.html { redirect_to organization_releases_path(@organization), alert: "Editing checklists requires a Pro plan or higher." }
      format.turbo_stream { redirect_to organization_releases_path(@organization), status: :see_other, alert: "Editing checklists requires a Pro plan or higher." }
      format.json { render json: { error: "Editing checklists requires a Pro plan or higher." }, status: :forbidden }
    end
  end

  def checklist_params
    params.require(:release_checklist).permit(:version_string, :platform, :notes)
  end

  def find_release_app
    case @checklist.listable_type
    when "AppleApp"
      @organization.apple_apps.find_by(id: @checklist.listable_id)
    when "AndroidApp"
      @organization.android_apps.find_by(id: @checklist.listable_id)
    end
  end
end
