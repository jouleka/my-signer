require "rails_helper"

RSpec.describe "SavedKeywordIdeas", type: :request do
  let(:org)     { create(:organization) }
  let(:user)    { org.owner }
  let(:ios_app) { create(:apple_app, organization: org) }

  before do
    user.update!(plan_tier: :pro)
    org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
    sign_in user
  end

  describe "POST /organizations/:org_id/apple_apps/:app_id/saved_keyword_ideas" do
    it "creates a normalized saved idea" do
      expect {
        post organization_apple_app_saved_keyword_ideas_path(org, ios_app),
             params: { saved_keyword_idea: { keyword: "  Focus   Timer " } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change { SavedKeywordIdea.count }.by(1)
      expect(SavedKeywordIdea.last.keyword).to eq("focus timer")
    end

    it "is denied on Free tier" do
      user.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      post organization_apple_app_saved_keyword_ideas_path(org, ios_app),
           params: { saved_keyword_idea: { keyword: "x" } }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "emits keyword_idea_saved audit" do
      expect {
        post organization_apple_app_saved_keyword_ideas_path(org, ios_app),
             params: { saved_keyword_idea: { keyword: "focus" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change { AuditEvent.where(action: "keyword_idea_saved").count }.by(1)
    end

    it "silently no-ops on duplicate (unique index)" do
      create(:saved_keyword_idea, apple_app: ios_app, keyword: "focus")
      expect {
        post organization_apple_app_saved_keyword_ideas_path(org, ios_app),
             params: { saved_keyword_idea: { keyword: "Focus" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.not_to change { SavedKeywordIdea.count }
    end
  end

  describe "DELETE /.../saved_keyword_ideas/:id" do
    it "destroys the idea and emits audit" do
      idea = create(:saved_keyword_idea, apple_app: ios_app)
      expect {
        delete organization_apple_app_saved_keyword_idea_path(org, ios_app, idea),
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change { SavedKeywordIdea.count }.by(-1)
       .and change { AuditEvent.where(action: "keyword_idea_removed").count }.by(1)
    end
  end

  describe "DELETE /.../saved_keyword_ideas/clear_all" do
    it "clears all for the app" do
      create_list(:saved_keyword_idea, 3, apple_app: ios_app)
      delete clear_all_organization_apple_app_saved_keyword_ideas_path(org, ios_app),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(SavedKeywordIdea.where(apple_app: ios_app).count).to eq(0)
    end
  end
end
