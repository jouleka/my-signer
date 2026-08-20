class SavedKeywordIdeasController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org
  before_action :authorize_org_access!
  before_action :set_app
  before_action :require_keyword_entitlement!
  after_action :verify_authorized

  # POST /.../saved_keyword_ideas
  def create
    @idea = @app.saved_keyword_ideas.new(saved_keyword_idea_params)
    @idea.added_by_user = current_user
    authorize @idea

    if @idea.save
      Audit::Logger.log(
        action: "keyword_idea_saved",
        organization: @organization,
        actor: current_user,
        resource: @idea,
        metadata: { keyword: @idea.keyword.to_s.truncate(100), apple_app_id: @app.id },
        request: request
      )
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "scratchpad",
            partial: "keywords/scratchpad",
            locals: {
              saved_keyword_ideas: @app.saved_keyword_ideas.order(created_at: :desc),
              apple_app: @app,
              organization: @organization,
              store_listing: scratchpad_store_listing,
              popularity_map: scratchpad_popularity_map
            }
          )
        end
        format.json { render json: { id: @idea.id, keyword: @idea.keyword }, status: :created }
      end
    elsif @idea.errors[:keyword].any? { |e| e.include?("already been taken") }
      head :ok
    else
      render json: { errors: @idea.errors }, status: :unprocessable_content
    end
  end

  # DELETE /.../saved_keyword_ideas/:id
  def destroy
    @idea = @app.saved_keyword_ideas.find(params[:id])
    authorize @idea

    keyword = @idea.keyword
    @idea.destroy!

    Audit::Logger.log(
      action: "keyword_idea_removed",
      organization: @organization,
      actor: current_user,
      resource: @idea,
      metadata: { keyword: keyword.to_s.truncate(100), apple_app_id: @app.id },
      request: request
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "scratchpad",
          partial: "keywords/scratchpad",
          locals: {
            saved_keyword_ideas: @app.saved_keyword_ideas.order(created_at: :desc),
            apple_app: @app,
            organization: @organization,
            store_listing: scratchpad_store_listing,
            popularity_map: scratchpad_popularity_map
          }
        )
      end
      format.json { head :no_content }
    end
  end

  # DELETE /.../saved_keyword_ideas/clear_all
  def clear_all
    # Authorize against the parent AppleApp rather than the SavedKeywordIdea
    # class — the policy's `org` resolver only handles instances, and we
    # already have a concrete app record in scope.
    authorize @app, :clear_all?, policy_class: SavedKeywordIdeaPolicy
    @app.saved_keyword_ideas.destroy_all

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "scratchpad",
          partial: "keywords/scratchpad",
          locals: {
            saved_keyword_ideas: [],
            apple_app: @app,
            organization: @organization,
            store_listing: scratchpad_store_listing,
            popularity_map: scratchpad_popularity_map
          }
        )
      end
      format.json { head :no_content }
    end
  end

  private

  def set_org
    # Scoped to memberships so non-member and non-existent ids both 404.
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def authorize_org_access!
    authorize @organization, :show?
  end

  def set_app
    @app = @organization.apple_apps.find(params[:apple_app_id])
  end

  def require_keyword_entitlement!
    return if @organization.entitlements.keyword_editor_enabled?
    respond_to do |format|
      format.html { redirect_to organization_keywords_path(@organization), alert: "Pro plan required." }
      format.any  { head :forbidden }
    end
  end

  def saved_keyword_idea_params
    params.require(:saved_keyword_idea).permit(:keyword)
  end

  # Scratchpad partial needs a locale-specific store_listing to check
  # "already in keywords" state. We default to the app's primary locale;
  # if the user is on a different locale in the Suggestions tab, the page
  # refresh will re-render with that locale's store_listing.
  def scratchpad_store_listing
    primary = @app.primary_locale || "en-US"
    @app.store_listings.find_by(locale: primary)
  end

  def scratchpad_popularity_map
    @app.apple_ads_recommendations.pluck(:keyword, :search_popularity).to_h
  end
end
