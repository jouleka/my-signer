require "rails_helper"
require "webmock/rspec"

RSpec.describe Aso::CompetitorLookup do
  let(:service) { described_class.new(app_id: 1016366447, country: "us") }

  before do
    Rails.cache.clear
    stub_request(:get, /itunes\.apple\.com\/lookup/)
      .to_return(
        status: 200,
        body: {
          resultCount: 1,
          results: [ {
            trackName: "Bear — Markdown Notes",
            sellerName: "Shiny Frog Ltd.",
            primaryGenreName: "Productivity",
            description: "Bear is a focused, flexible writing app. Use it for notes, sketches, essays."
          } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  after { Rails.cache.clear }

  it "fetches and normalizes the lookup response" do
    result = service.fetch
    expect(result[:track_name]).to eq("Bear — Markdown Notes")
    expect(result[:primary_genre]).to eq("Productivity")
    expect(result[:seller_name]).to eq("Shiny Frog Ltd.")
    expect(result[:seed_terms]).to include("bear", "markdown", "notes")
  end

  it "caches by (app_id, country) for 24h" do
    memory_store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(memory_store)
    2.times { service.fetch }
    expect(WebMock).to have_requested(:get, /itunes\.apple\.com\/lookup/).once
  end

  it "returns nil on upstream failure" do
    stub_request(:get, /itunes\.apple\.com\/lookup/).to_return(status: 500)
    Rails.cache.clear
    expect(described_class.new(app_id: 999, country: "us").fetch).to be_nil
  end

  it "rejects invalid app_id" do
    expect(described_class.new(app_id: "bogus", country: "us").fetch).to be_nil
  end
end
