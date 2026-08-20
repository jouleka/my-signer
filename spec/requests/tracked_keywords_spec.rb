require "rails_helper"

RSpec.describe "TrackedKeywords", type: :request do
  let(:user)       { create(:user, :pro_plan) }
  let(:org)        { create(:organization, owner: user) }
  let(:ios_app)    { create(:apple_app, organization: org) }
  let(:other_user) { create(:user, :pro_plan) }
  let(:other_org)  { create(:organization, owner: other_user) }
  let(:other_app)  { create(:apple_app, organization: other_org) }

  before { sign_in user, scope: :user }

  describe "POST create" do
    it "creates a TrackedKeyword + TrackedKeywordCountry" do
      expect {
        post organization_apple_app_tracked_keywords_path(org, ios_app),
             params: { tracked_keyword: { keyword: "photo editor", countries: [ "us" ] } }
      }.to change { TrackedKeyword.count }.by(1)
         .and change { TrackedKeywordCountry.count }.by(1)
    end

    it "normalizes the keyword" do
      post organization_apple_app_tracked_keywords_path(org, ios_app),
           params: { tracked_keyword: { keyword: "  Photo  Editor  ", countries: [ "us" ] } }
      expect(TrackedKeyword.last.keyword).to eq("photo editor")
    end

    it "returns 200 Turbo Stream on success" do
      post organization_apple_app_tracked_keywords_path(org, ios_app),
           params: { tracked_keyword: { keyword: "photo editor", countries: [ "us" ] } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
    end

    it "returns 422 on over-country-limit (Pro = 3)" do
      expect {
        post organization_apple_app_tracked_keywords_path(org, ios_app),
             params: { tracked_keyword: { keyword: "x", countries: %w[us gb au de] } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.not_to change { TrackedKeyword.count }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 on exceeding total-keyword-limit (Pro = 50)" do
      # Seed 50 existing tracked keyword-country pairs
      50.times do |i|
        tk = create(:tracked_keyword, apple_app: ios_app, keyword: "k#{i}")
        create(:tracked_keyword_country, tracked_keyword: tk, country: "us")
      end
      expect {
        post organization_apple_app_tracked_keywords_path(org, ios_app),
             params: { tracked_keyword: { keyword: "one_more", countries: [ "us" ] } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.not_to change { TrackedKeyword.count }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "redirects on Free-tier entitlement denial" do
      user.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      post organization_apple_app_tracked_keywords_path(org, ios_app),
           params: { tracked_keyword: { keyword: "x", countries: [ "us" ] } }
      expect(response).to redirect_to(pricing_path)
    end

    it "rejects cross-org access" do
      # ApplicationController rescues Pundit::NotAuthorizedError and redirects
      # with an "unauthorized" flash. ActiveRecord::RecordNotFound produces
      # a 404. Either outcome is acceptable -- both represent cross-org denial.
      post organization_apple_app_tracked_keywords_path(other_org, other_app),
           params: { tracked_keyword: { keyword: "x", countries: [ "us" ] } }
      expect(TrackedKeyword.count).to eq(0)
      expect(response.status).to be_in([ 302, 403, 404 ])
      if response.status == 302
        expect(flash[:alert]).to include("not authorized").or include("Not authorized")
      end
    end

    it "does NOT allow mass-assignment of server-controlled fields" do
      post organization_apple_app_tracked_keywords_path(org, ios_app),
           params: { tracked_keyword: {
             keyword: "x",
             countries: [ "us" ],
             search_popularity: 99,
             enabled: false
           } }
      tk = TrackedKeyword.last
      expect(tk.search_popularity).to be_nil
      expect(tk.enabled).to be true
    end

    it "logs a tracked_keyword_added audit event" do
      expect(Audit::Logger).to receive(:log).with(
        hash_including(action: :tracked_keyword_added, organization: org, actor: user)
      )
      post organization_apple_app_tracked_keywords_path(org, ios_app),
           params: { tracked_keyword: { keyword: "x", countries: [ "us" ] } }
    end
  end

  describe "DELETE destroy" do
    let!(:tk)  { create(:tracked_keyword, apple_app: ios_app, keyword: "kill me") }
    let!(:tkc) { create(:tracked_keyword_country, tracked_keyword: tk, country: "us") }

    it "destroys the TrackedKeyword" do
      expect {
        delete organization_apple_app_tracked_keyword_path(org, ios_app, tk)
      }.to change { TrackedKeyword.count }.by(-1)
    end

    it "logs a tracked_keyword_removed audit event" do
      expect(Audit::Logger).to receive(:log).with(
        hash_including(action: :tracked_keyword_removed, organization: org, actor: user)
      )
      delete organization_apple_app_tracked_keyword_path(org, ios_app, tk)
    end

    it "succeeds when history exists, preserving rankings via nullify" do
      # The outer let!(:tkc) already created a (tk, "us") pair; reuse it here.
      KeywordRanking.create!(
        organization: org,
        tracked_keyword_country: tkc,
        keyword: tk.keyword,
        rank: 10,
        checked_on: Date.current
      )
      expect {
        delete organization_apple_app_tracked_keyword_path(org, ios_app, tk)
      }.to change { TrackedKeyword.count }.by(-1)

      # Ranking preserved (FK nullified) — Retention job cleans up later
      ranking = KeywordRanking.where(keyword: tk.keyword).first
      expect(ranking).to be_present
      expect(ranking.tracked_keyword_country_id).to be_nil
    end

    it "allows destroy even on Free tier (post-downgrade cleanup)" do
      org.owner.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      expect {
        delete organization_apple_app_tracked_keyword_path(org, ios_app, tk)
      }.to change { TrackedKeyword.count }.by(-1)
    end
  end

  describe "GET show (Turbo Frame detail)" do
    let(:tk) { create(:tracked_keyword, apple_app: ios_app) }

    it "renders the detail partial" do
      # The detail partial will be created in Phase 4. Skip until then.
      pending "detail partial created in Phase 4" unless File.exist?(Rails.root.join("app/views/keywords/_tracked_keyword_detail.html.erb"))
      get organization_apple_app_tracked_keyword_path(org, ios_app, tk)
      expect(response).to have_http_status(:ok)
    end
  end
end
