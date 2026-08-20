require "rails_helper"

RSpec.describe "Analytics", type: :request do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }

  before { sign_in user, scope: :user }

  describe "GET /organizations/:organization_id/analytics" do
    it "loads the analytics index without crashing" do
      get organization_analytics_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it "does not crash when the plan's max_analytics_history_days is below the smallest preset" do
      # I-DSH-3: the controller intersects [7, 14, 30, 90, 365] against the
      # plan's history ceiling. If the ceiling is below 7, the result was empty
      # and `@days = nil` blew up downstream on `@days.days.ago`.
      #
      # Stub the controller's entitlements lookup directly rather than using
      # allow_any_instance_of (which would also affect any other Organization
      # instance loaded during the request, e.g. memberships).
      tiny_entitlements = Pricing::Entitlements.new("free")
      allow(tiny_entitlements).to receive(:max_analytics_history_days).and_return(3)
      allow_any_instance_of(AnalyticsController)
        .to receive(:entitlements_for_request).and_return(tiny_entitlements) if AnalyticsController.private_method_defined?(:entitlements_for_request)
      # Direct, non-flaky path: stub the specific Organization the controller will load.
      allow(Organization).to receive(:find).and_call_original
      allow(Organization).to receive(:find).with(organization.id.to_s).and_return(organization)
      allow(organization).to receive(:entitlements).and_return(tiny_entitlements)

      get organization_analytics_path(organization)

      expect(response).to have_http_status(:ok)
    end
  end
end
