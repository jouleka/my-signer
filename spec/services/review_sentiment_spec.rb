require "rails_helper"

RSpec.describe ReviewSentiment do
  describe ".classify" do
    it "returns negative for 1 star" do
      expect(described_class.classify(rating: 1)).to eq("negative")
    end

    it "returns negative for 2 stars" do
      expect(described_class.classify(rating: 2)).to eq("negative")
    end

    it "returns neutral for 3 stars" do
      expect(described_class.classify(rating: 3)).to eq("neutral")
    end

    it "returns positive for 4 stars" do
      expect(described_class.classify(rating: 4)).to eq("positive")
    end

    it "returns positive for 5 stars" do
      expect(described_class.classify(rating: 5)).to eq("positive")
    end

    it "returns neutral for out of range" do
      expect(described_class.classify(rating: 0)).to eq("neutral")
      expect(described_class.classify(rating: 6)).to eq("neutral")
    end
  end
end
