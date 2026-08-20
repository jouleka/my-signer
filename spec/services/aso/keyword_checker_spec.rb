require "rails_helper"

RSpec.describe Aso::KeywordChecker do
  let(:org) { create(:organization) }
  let(:app) { create(:apple_app, organization: org, app_store_id: "1149994032") }
  let(:full_body) { File.read(Rails.root.join("spec/fixtures/aso/mzstore_woa_search_response.json")) }
  let(:empty_body) { File.read(Rails.root.join("spec/fixtures/aso/mzstore_woa_empty_response.json")) }

  before { Rails.cache.clear; allow(Aso::RateLimiter).to receive(:acquire).and_return(true) }

  # Stub helper: captures headers/params inside the .get block
  def stub_faraday(body:, success: true)
    req = double("Faraday::Request").tap do |r|
      allow(r).to receive(:headers).and_return({})
      allow(r).to receive(:params).and_return({})
    end
    response = instance_double(Faraday::Response, success?: success, body: body)
    conn = instance_double(Faraday::Connection)
    allow(Faraday).to receive(:new).and_return(conn)
    allow(conn).to receive(:get).and_yield(req).and_return(response)
    req
  end

  describe "#check" do
    it "returns rank + total_count when the app is found in results" do
      stub_faraday(body: full_body)
      result = described_class.new(app: app, keyword: "photo editor", country: "us").check
      expect(result).to include(:rank, :total_count)
      expect(result[:rank]).to be_a(Integer)
      expect(result[:rank]).to be_between(1, 250)
      expect(result[:total_count]).to be_a(Integer)
    end

    it "returns rank: nil + total_count when app is not in results" do
      unknown_app = create(:apple_app, organization: org, app_store_id: "99999999999", sku: "other")
      stub_faraday(body: full_body)
      result = described_class.new(app: unknown_app, keyword: "photo editor", country: "us").check
      expect(result[:rank]).to be_nil
      expect(result[:total_count]).to be > 0
    end

    it "returns :rate_limited when Aso::RateLimiter.acquire returns false" do
      allow(Aso::RateLimiter).to receive(:acquire).and_return(false)
      expect(described_class.new(app: app, keyword: "foo", country: "us").check).to eq(:rate_limited)
    end

    it "returns :rate_limited when Apple returns 200 with empty bubble results (soft block)" do
      stub_faraday(body: empty_body)
      expect(described_class.new(app: app, keyword: "obscure", country: "us").check).to eq(:rate_limited)
    end

    it "returns :network_error on Faraday connection failure" do
      conn = instance_double(Faraday::Connection)
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:get).and_raise(Faraday::ConnectionFailed.new("refused"))
      expect(described_class.new(app: app, keyword: "foo", country: "us").check).to eq(:network_error)
    end

    it "returns :network_error on HTTP non-2xx" do
      stub_faraday(body: "", success: false)
      expect(described_class.new(app: app, keyword: "foo", country: "us").check).to eq(:network_error)
    end

    it "returns :network_error on malformed JSON" do
      stub_faraday(body: "this is not json")
      expect(described_class.new(app: app, keyword: "foo", country: "us").check).to eq(:network_error)
    end

    it "sends the X-Apple-Store-Front header in the facundoolano format" do
      req = stub_faraday(body: full_body)
      described_class.new(app: app, keyword: "foo", country: "us").check
      expect(req.headers["X-Apple-Store-Front"]).to eq("143441,24 t:native")
    end

    it "uses the correct storefront for non-US countries" do
      req = stub_faraday(body: full_body)
      described_class.new(app: app, keyword: "foto", country: "de").check
      expect(req.headers["X-Apple-Store-Front"]).to eq("143443,24 t:native")
      expect(req.params["country"]).to eq("de")
    end

    it "falls back to US storefront for unknown country" do
      req = stub_faraday(body: full_body)
      described_class.new(app: app, keyword: "x", country: "xx").check
      expect(req.headers["X-Apple-Store-Front"]).to eq("143441,24 t:native")
    end

    it "sends correct query params" do
      req = stub_faraday(body: full_body)
      described_class.new(app: app, keyword: "photo editor", country: "us").check
      expect(req.params["clientApplication"]).to eq("Software")
      expect(req.params["media"]).to eq("software")
      expect(req.params["term"]).to eq("photo editor")
    end

    it "caches successful non-empty responses for 6 hours (cross-call dedup)" do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_store)
      stub_faraday(body: full_body)
      2.times { described_class.new(app: app, keyword: "foo", country: "us").check }
      expect(Faraday).to have_received(:new).once
    end

    it "does NOT cache empty-result responses" do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_store)
      stub_faraday(body: empty_body)
      2.times { described_class.new(app: app, keyword: "x", country: "us").check }
      expect(Faraday).to have_received(:new).twice
    end

    it "does NOT cache network errors" do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_store)
      stub_faraday(body: "", success: false)
      2.times { described_class.new(app: app, keyword: "x", country: "us").check }
      expect(Faraday).to have_received(:new).twice
    end
  end
end
