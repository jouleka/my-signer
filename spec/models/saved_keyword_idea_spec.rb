require "rails_helper"

RSpec.describe SavedKeywordIdea, type: :model do
  describe "validations" do
    it "requires a keyword" do
      idea = build(:saved_keyword_idea, keyword: nil)
      expect(idea).not_to be_valid
      expect(idea.errors[:keyword]).to include("can't be blank")
    end

    it "caps keyword at 100 characters" do
      idea = build(:saved_keyword_idea, keyword: "x" * 101)
      expect(idea).not_to be_valid
    end

    it "enforces uniqueness scoped to apple_app via normalized value" do
      app = create(:apple_app)
      create(:saved_keyword_idea, apple_app: app, keyword: "Focus Timer")
      dup = build(:saved_keyword_idea, apple_app: app, keyword: "focus  timer")
      expect(dup).not_to be_valid
      expect(dup.errors[:keyword]).to include("has already been taken")
    end
  end

  describe "normalization" do
    it "downcases and collapses whitespace before save" do
      idea = create(:saved_keyword_idea, keyword: "  Focus   Timer ")
      expect(idea.reload.keyword).to eq("focus timer")
    end
  end

  describe "associations" do
    it "belongs to an apple_app" do
      expect(described_class.reflect_on_association(:apple_app).macro).to eq(:belongs_to)
    end

    it "belongs to an optional added_by_user" do
      reflection = described_class.reflect_on_association(:added_by_user)
      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.options[:optional]).to be true
      expect(reflection.options[:class_name]).to eq("User")
    end

    it "survives user deletion by nullifying added_by_user_id" do
      user = create(:user)
      idea = create(:saved_keyword_idea, added_by_user: user)
      user.destroy!
      expect(idea.reload.added_by_user_id).to be_nil
    end

    it "is destroyed when the parent apple_app is destroyed" do
      app = create(:apple_app)
      create(:saved_keyword_idea, apple_app: app)
      expect { app.destroy! }.to change { SavedKeywordIdea.count }.by(-1)
    end
  end
end
