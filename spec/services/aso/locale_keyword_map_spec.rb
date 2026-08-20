require "rails_helper"

RSpec.describe Aso::LocaleKeywordMap do
  let(:organization) { create(:organization) }
  let(:apple_app) { create(:apple_app, organization: organization) }

  describe "#build" do
    it "builds correct map from store listings" do
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "en-US", keywords: "productivity,tools,utility")
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "de-DE", keywords: "produktivitaet,werkzeuge")

      result = described_class.new(apple_app: apple_app).build

      expect(result[:locales]).to contain_exactly("de-DE", "en-US")
      expect(result[:keywords_by_locale]["en-US"]).to eq([ "productivity", "tools", "utility" ])
      expect(result[:keywords_by_locale]["de-DE"]).to eq([ "produktivitaet", "werkzeuge" ])
      expect(result[:all_keywords]).to include("productivity", "tools", "utility", "produktivitaet", "werkzeuge")
    end

    it "identifies gaps (locales with no keywords)" do
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "en-US", keywords: "productivity,tools")
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "fr-FR", keywords: nil)

      result = described_class.new(apple_app: apple_app).build

      expect(result[:gaps]).to eq([ "fr-FR" ])
    end

    it "identifies relevant pool groups" do
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "en-US", keywords: "productivity")
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "en-GB", keywords: "tools")

      result = described_class.new(apple_app: apple_app).build

      expect(result[:pool_groups]).to include(%w[en-US en-CA en-AU en-GB])
    end

    it "returns empty pool groups when no locales share a pool" do
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "en-US", keywords: "productivity")
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "de-DE", keywords: "tools")

      result = described_class.new(apple_app: apple_app).build

      expect(result[:pool_groups]).to be_empty
    end

    it "deduplicates keywords across locales" do
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "en-US", keywords: "Productivity,Tools")
      create(:store_listing, :ios, organization: organization, listable: apple_app,
             locale: "en-GB", keywords: "productivity,utility")

      result = described_class.new(apple_app: apple_app).build

      expect(result[:all_keywords]).to eq([ "productivity", "tools", "utility" ])
    end

    it "handles app with no listings" do
      result = described_class.new(apple_app: apple_app).build

      expect(result[:locales]).to be_empty
      expect(result[:keywords_by_locale]).to be_empty
      expect(result[:gaps]).to be_empty
      expect(result[:all_keywords]).to be_empty
    end
  end
end
