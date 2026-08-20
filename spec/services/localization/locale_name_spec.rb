require "rails_helper"

RSpec.describe Localization::LocaleName do
  describe ".human" do
    it "returns the language name for a language-only tag" do
      expect(described_class.human("ja")).to eq("Japanese")
    end

    it "disambiguates language + region (the en-CA AI confusion case)" do
      expect(described_class.human("en-CA")).to eq("English (Canada)")
      expect(described_class.human("fr-CA")).to eq("French (Canada)")
    end

    it "disambiguates language + script" do
      expect(described_class.human("zh-Hans")).to eq("Chinese (Simplified)")
      expect(described_class.human("zh-Hant")).to eq("Chinese (Traditional)")
    end

    it "combines script + region" do
      expect(described_class.human("zh-Hans-CN")).to eq("Chinese (Simplified, China)")
    end

    it "falls back to the original tag when unknown" do
      expect(described_class.human("xx-YY")).to eq("xx-YY")
    end

    it "handles blank input gracefully" do
      expect(described_class.human(nil)).to eq("")
      expect(described_class.human("")).to eq("")
    end
  end

  describe ".prompt_label" do
    it "returns tag + human form for known locales" do
      expect(described_class.prompt_label("en-CA")).to eq("en-CA (English, Canada)")
    end

    it "returns just the tag when unknown (no parenthetical duplicate)" do
      expect(described_class.prompt_label("xx-YY")).to eq("xx-YY")
    end
  end
end
