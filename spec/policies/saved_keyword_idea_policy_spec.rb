require "rails_helper"

RSpec.describe SavedKeywordIdeaPolicy, type: :policy do
  let(:user)  { create(:user, :pro_plan) }
  let(:org)   { create(:organization, owner: user) }
  let(:app)   { create(:apple_app, organization: org) }
  let(:idea)  { create(:saved_keyword_idea, apple_app: app) }

  subject { described_class.new(user, idea) }

  describe "#show? / #create?" do
    it "is permitted for org members on Pro+" do
      expect(subject.show?).to be true
      expect(subject.create?).to be true
    end

    it "is denied on Free tier" do
      user.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      expect(subject.show?).to be false
      expect(subject.create?).to be false
    end

    it "is denied for strangers" do
      other = create(:user)
      expect(described_class.new(other, idea).show?).to be false
    end
  end

  describe "#destroy?" do
    it "permits destroy even after downgrade (for cleanup)" do
      user.update!(plan_tier: :free)
      org.reset_entitlements_memo! if org.respond_to?(:reset_entitlements_memo!)
      expect(subject.destroy?).to be true
    end

    it "denies destroy for strangers" do
      other = create(:user)
      expect(described_class.new(other, idea).destroy?).to be false
    end
  end

  describe "Scope" do
    it "returns only ideas for apps in accessible orgs" do
      create(:saved_keyword_idea)
      result = Pundit.policy_scope(user, SavedKeywordIdea)
      expect(result).to eq([ idea ])
    end
  end
end
