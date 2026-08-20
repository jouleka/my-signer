class ReviewResponseTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :authorize_org_access!
  before_action :require_review_monitoring!
  before_action :require_response_templates!, only: [ :create, :update, :destroy ]
  after_action :verify_authorized

  # POST /organizations/:organization_id/review_response_templates
  def create
    authorize @organization, :manage_resources?

    template = @organization.review_response_templates.build(template_params)

    if template.save
      respond_to do |format|
        format.html { redirect_to organization_reviews_path(@organization), notice: "Template created." }
        format.json { render json: template, status: :created }
        format.turbo_stream {
          redirect_to organization_reviews_path(@organization), notice: "Template created."
        }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_reviews_path(@organization), alert: template.errors.full_messages.to_sentence }
        format.json { render json: { errors: template.errors.full_messages }, status: :unprocessable_content }
        format.turbo_stream {
          redirect_to organization_reviews_path(@organization), alert: template.errors.full_messages.to_sentence
        }
      end
    end
  end

  # PATCH /organizations/:organization_id/review_response_templates/:id
  def update
    authorize @organization, :manage_resources?

    template = @organization.review_response_templates.find(params[:id])

    if template.update(template_params)
      respond_to do |format|
        format.html { redirect_to organization_reviews_path(@organization), notice: "Template updated." }
        format.json { render json: template }
        format.turbo_stream {
          redirect_to organization_reviews_path(@organization), notice: "Template updated."
        }
      end
    else
      respond_to do |format|
        format.html { redirect_to organization_reviews_path(@organization), alert: template.errors.full_messages.to_sentence }
        format.json { render json: { errors: template.errors.full_messages }, status: :unprocessable_content }
        format.turbo_stream {
          redirect_to organization_reviews_path(@organization), alert: template.errors.full_messages.to_sentence
        }
      end
    end
  end

  # DELETE /organizations/:organization_id/review_response_templates/:id
  def destroy
    authorize @organization, :manage_resources?

    template = @organization.review_response_templates.find(params[:id])
    template.destroy

    respond_to do |format|
      format.html { redirect_to organization_reviews_path(@organization), notice: "Template deleted." }
      format.json { head :no_content }
      format.turbo_stream {
        redirect_to organization_reviews_path(@organization), notice: "Template deleted."
      }
    end
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def authorize_org_access!
    authorize @organization, :show?
  end

  def require_review_monitoring!
    return if @organization.entitlements.review_monitoring_enabled?

    redirect_to organization_reviews_path(@organization),
      alert: "Review monitoring is not available on your current plan."
  end

  def require_response_templates!
    return if @organization.entitlements.response_templates_enabled?

    respond_to do |format|
      format.html {
        redirect_to organization_reviews_path(@organization),
          alert: "Response templates require a Pro plan or higher."
      }
      format.json {
        render json: { error: "Response templates require a Pro plan or higher." }, status: :forbidden
      }
      format.turbo_stream {
        redirect_to organization_reviews_path(@organization),
          alert: "Response templates require a Pro plan or higher."
      }
    end
  end

  def template_params
    params.require(:review_response_template).permit(:name, :category, :body, :position)
  end
end
