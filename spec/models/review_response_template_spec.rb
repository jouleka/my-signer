require "rails_helper"

RSpec.describe ReviewResponseTemplate, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      template = build(:review_response_template)
      expect(template).to be_valid
    end

    it "requires name" do
      template = build(:review_response_template, name: nil)
      expect(template).not_to be_valid
    end

    it "requires body" do
      template = build(:review_response_template, body: nil)
      expect(template).not_to be_valid
    end

    it "enforces body max length of 350" do
      template = build(:review_response_template, body: "x" * 351)
      expect(template).not_to be_valid
      expect(template.errors[:body]).to be_present
    end

    it "allows body at exactly 350 characters" do
      template = build(:review_response_template, body: "x" * 350)
      expect(template).to be_valid
    end

    it "requires category in valid list" do
      template = build(:review_response_template, category: "invalid_cat")
      expect(template).not_to be_valid
    end

    it "accepts all valid categories" do
      ReviewResponseTemplate::CATEGORIES.each do |cat|
        template = build(:review_response_template, category: cat)
        expect(template).to be_valid
      end
    end
  end

  describe "CATEGORIES constant" do
    it "includes expected categories" do
      expect(ReviewResponseTemplate::CATEGORIES).to match_array(
        %w[bug_report feature_request praise complaint general]
      )
    end
  end
end
