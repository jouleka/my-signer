class TrackedKeywordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org_and_app
  before_action :authorize_org_access!
  # Skip entitlement on destroy so Free-tier users can clean up stranded
  # keywords after downgrade (aligned with TrackedKeywordPolicy#destroy?).
  before_action :require_keyword_tracking_entitlement!, except: [ :destroy ]
  before_action :enforce_tracking_limits!, only: [ :create ]
  after_action :verify_authorized

  # GET /organizations/:organization_id/apple_apps/:apple_app_id/tracked_keywords/:id
  # Turbo Frame endpoint -- returns the expanded detail partial.
  def show
    @tracked_keyword = @app.tracked_keywords.find(params[:id])
    authorize @tracked_keyword
    render partial: "keywords/tracked_keyword_detail", locals: { tk: @tracked_keyword }
  end

  # POST /organizations/:organization_id/apple_apps/:apple_app_id/tracked_keywords
  def create
    @tracked_keyword = @app.tracked_keywords.build(keyword: permitted[:keyword])
    authorize @tracked_keyword

    ActiveRecord::Base.transaction do
      @tracked_keyword.save!
      permitted[:countries].each do |cc|
        @tracked_keyword.tracked_keyword_countries.create!(country: cc)
      end
    end

    Audit::Logger.log(
      action: :tracked_keyword_added,
      organization: @organization,
      actor: current_user,
      metadata: {
        keyword: @tracked_keyword.keyword.to_s.truncate(100),
        countries: permitted[:countries]
      }
    )

    # Drives the post-add confirmation banner in create.turbo_stream.erb.
    @next_check_estimate = Aso::NextCheckEstimator.for(organization: @organization)

    respond_to do |format|
      format.turbo_stream # renders create.turbo_stream.erb
      format.html do
        redirect_to organization_keyword_path(@organization, "apple_app_#{@app.id}", tab: "tracking"),
          notice: "Tracked keyword added."
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    @error_message = e.message
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "add-tracked-keyword-modal-errors",
          partial: "tracked_keywords/errors",
          locals: { error: @error_message }
        ), status: :unprocessable_content
      end
      format.html do
        redirect_to organization_keyword_path(@organization, "apple_app_#{@app.id}", tab: "tracking"),
          alert: @error_message
      end
    end
  end

  # DELETE /organizations/:organization_id/apple_apps/:apple_app_id/tracked_keywords/:id
  def destroy
    @tracked_keyword = @app.tracked_keywords.find(params[:id])
    authorize @tracked_keyword
    kw = @tracked_keyword.keyword
    @tracked_keyword.destroy!

    Audit::Logger.log(
      action: :tracked_keyword_removed,
      organization: @organization,
      actor: current_user,
      metadata: { keyword: kw.to_s.truncate(100) }
    )

    respond_to do |format|
      format.turbo_stream # renders destroy.turbo_stream.erb
      format.html do
        redirect_to organization_keyword_path(@organization, "apple_app_#{@app.id}", tab: "tracking"),
          notice: "Keyword removed."
      end
    end
  end

  private

  def set_org_and_app
    # Scoped to memberships so non-member and non-existent ids both 404.
    @organization = current_user.organizations.find(params[:organization_id])
    @app = @organization.apple_apps.find(params[:apple_app_id])
    # Exposed so Turbo Stream templates re-rendering the tracking partials
    # (which read @entitlements for the limit banner + modal field caps)
    # have the same data the originating keywords#show action provides.
    @entitlements = @organization.entitlements
  end

  def authorize_org_access!
    authorize @organization, :show?
  end

  def require_keyword_tracking_entitlement!
    return if @organization.entitlements.keyword_editor_enabled?

    # authorize_org_access! already called authorize earlier, satisfying
    # verify_authorized. Just redirect.
    redirect_to pricing_path, alert: "Keyword tracking requires a Pro plan or higher."
  end

  def enforce_tracking_limits!
    ent = @organization.entitlements
    countries = Array(permitted[:countries])

    if countries.empty?
      redirect_back_with_error("Pick at least one country.")
      return
    end

    if countries.size > ent.max_countries_per_tracked_keyword
      redirect_back_with_error(
        "Your plan allows #{ent.max_countries_per_tracked_keyword} countries per keyword."
      )
      return
    end

    current_pairs = TrackedKeywordCountry
                      .joins(:tracked_keyword)
                      .where(tracked_keywords: { apple_app_id: @app.id })
                      .count
    if current_pairs + countries.size > ent.max_tracked_keywords_per_app
      redirect_back_with_error(
        "You'd exceed your #{ent.max_tracked_keywords_per_app} tracked-keyword limit."
      )
      nil
    end
  end

  def redirect_back_with_error(msg)
    # authorize_org_access! already called authorize earlier, satisfying
    # verify_authorized. Just respond.
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "add-tracked-keyword-modal-errors",
          partial: "tracked_keywords/errors",
          locals: { error: msg }
        ), status: :unprocessable_content
      end
      format.html do
        redirect_to organization_keyword_path(@organization, "apple_app_#{@app.id}", tab: "tracking"),
          alert: msg
      end
    end
  end

  def permitted
    @permitted ||= params.require(:tracked_keyword).permit(:keyword, countries: [])
  end
end
