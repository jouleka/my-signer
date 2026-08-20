require "rails_helper"

RSpec.describe Aso::KeywordNormalizer do
  describe ".call" do
    it "applies NFC" do
      # "Café" can be composed (é = U+00E9) or decomposed (e + U+0301)
      decomposed = "Cafe\u0301"
      expect(described_class.call(decomposed)).to eq("café".unicode_normalize(:nfc))
    end

    it "downcases" do
      expect(described_class.call("Photo Editor")).to eq("photo editor")
    end

    it "strips leading/trailing whitespace" do
      expect(described_class.call("  photo  ")).to eq("photo")
    end

    it "collapses internal whitespace runs" do
      expect(described_class.call("photo    editor")).to eq("photo editor")
    end

    it "handles tabs + newlines as whitespace" do
      expect(described_class.call("photo\t\neditor")).to eq("photo editor")
    end

    it "returns empty string for nil" do
      expect(described_class.call(nil)).to eq("")
    end

    it "returns empty string for blank" do
      expect(described_class.call("   ")).to eq("")
    end

    it "is idempotent" do
      s = "  PHOTO   editor "
      expect(described_class.call(described_class.call(s))).to eq(described_class.call(s))
    end
  end
end
