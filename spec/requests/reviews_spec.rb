require "rails_helper"

RSpec.describe "Reviews", type: :request do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }

  before do
    sign_in user, scope: :user
  end

  describe "GET /organizations/:organization_id/reviews" do
    it "loads the reviews index" do
      get organization_reviews_path(organization)
      expect(response).to have_http_status(:ok)
    end

    it "redirects unauthenticated users" do
      sign_out user
      get organization_reviews_path(organization)
      expect(response).to redirect_to(new_user_session_path)
    end

    context "with free plan" do
      let(:user) { create(:user, plan_tier: :free) }

      it "shows reviews page (free gets 1 app)" do
        get organization_reviews_path(organization)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Reviews &amp; Ratings")
      end
    end

    context "with pro plan and reviews" do
      let!(:positive_review) { create(:app_review, organization: organization, reviewable: apple_app, rating: 5) }
      let!(:negative_review) { create(:app_review, :negative, organization: organization, reviewable: apple_app) }

      it "shows the review feed" do
        get organization_reviews_path(organization)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Reviews &amp; Ratings")
      end

      it "shows stats" do
        get organization_reviews_path(organization)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Total Reviews")
        expect(response.body).to include("Average Rating")
      end

      it "filters by platform" do
        get organization_reviews_path(organization, platform: "apple")
        expect(response).to have_http_status(:ok)
      end

      it "filters by rating" do
        get organization_reviews_path(organization, rating: "5")
        expect(response).to have_http_status(:ok)
      end

      it "filters by sentiment" do
        get organization_reviews_path(organization, sentiment: "negative")
        expect(response).to have_http_status(:ok)
      end

      it "paginates" do
        get organization_reviews_path(organization, page: 1)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST /organizations/:organization_id/reviews/:id/reply" do
    let!(:review) { create(:app_review, organization: organization, reviewable: apple_app) }

    it "enqueues a reply job" do
      post reply_organization_review_path(organization, review),
           params: { reply_text: "Thanks for your review!" }

      expect(response).to redirect_to(organization_reviews_path(organization))
      review.reload
      expect(review.reply_status).to eq("pending")
      expect(review.reply_text).to eq("Thanks for your review!")
    end

    it "rejects blank reply text" do
      post reply_organization_review_path(organization, review),
           params: { reply_text: "" }

      expect(response).to redirect_to(organization_reviews_path(organization))
      expect(flash[:alert]).to include("blank")
    end

    it "rejects reply text over the platform char limit" do
      post reply_organization_review_path(organization, review),
           params: { reply_text: "x" * 5971 }

      expect(response).to redirect_to(organization_reviews_path(organization))
      expect(flash[:alert]).to include("5970")
    end
  end

  describe "POST /organizations/:organization_id/reviews/sync" do
    it "enqueues a sync job and redirects" do
      expect {
        post sync_organization_reviews_path(organization)
      }.to have_enqueued_job(ReviewSyncJob).with(organization_id: organization.id)

      expect(response).to redirect_to(organization_reviews_path(organization))
      expect(flash[:notice]).to include("sync started")
    end
  end

  describe "authorization" do
    let(:other_user) { create(:user) }
    let(:other_org) { create(:organization, owner: other_user) }

    it "prevents access to other organization's reviews" do
      get organization_reviews_path(other_org)
      # set_org now scopes the lookup to current_user.organizations, so a
      # non-member sees 404 — same response as a non-existent id, which
      # closes the enumeration oracle (302/redirect = exists but not mine;
      # 404 = doesn't exist). See OrganizationsController#set_organization.
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "XSS escaping of reply_text" do
    # I-DSH-6: iOS allows reply text up to 5970 chars, much longer than the
    # 350-char Google Play limit. Whatever a developer types is rendered into
    # the reviews index — a <script> in there must NOT execute.
    it "renders reply_text with HTML entities escaped" do
      malicious = "<script>alert(1)</script>"
      review = create(:app_review, organization: organization, reviewable: apple_app)
      review.update!(reply_text: malicious, reply_status: "posted", reply_posted_at: 1.hour.ago)

      get organization_reviews_path(organization)

      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
      expect(response.body).not_to include("<script>alert(1)</script>")
    end
  end
end
