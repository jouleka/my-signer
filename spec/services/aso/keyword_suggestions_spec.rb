require "rails_helper"

RSpec.describe Aso::KeywordSuggestions do
  let(:plist_response) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="no"?>
      <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
        <dict>
          <key>title</key>
          <string>Suggestions</string>
          <key>hints</key>
          <array>
            <dict>
              <key>term</key>
              <string>photo editor</string>
              <key>url</key>
              <string>https://search.itunes.apple.com/foo</string>
            </dict>
            <dict>
              <key>term</key>
              <string>photoshop</string>
              <key>url</key>
              <string>https://search.itunes.apple.com/bar</string>
            </dict>
          </array>
        </dict>
      </plist>
    XML
  end

  let(:empty_plist_response) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="no"?>
      <plist version="1.0">
        <dict>
          <key>hints</key>
          <array/>
        </dict>
      </plist>
    XML
  end

  # Simulates Faraday: captures headers/params set inside the .get block so tests
  # can assert on them, and returns a double acting as the response.
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

  before { Rails.cache.clear }

  describe "#fetch" do
    it "returns an empty array for blank or whitespace-only term" do
      expect(described_class.new(term: "").fetch).to eq([])
      expect(described_class.new(term: "   ").fetch).to eq([])
    end

    it "parses term strings out of Apple's XML plist response" do
      stub_faraday(body: plist_response)

      expect(described_class.new(term: "photo", country: "us").fetch).to eq([ "photo editor", "photoshop" ])
    end

    it "sends the X-Apple-Store-Front header (required by Apple — without it hints is empty)" do
      req = stub_faraday(body: plist_response)

      described_class.new(term: "photo", country: "us").fetch

      expect(req.headers["X-Apple-Store-Front"]).to eq("143441-1,29")
    end

    it "passes the country URL param so Apple returns country-specific hints" do
      req = stub_faraday(body: plist_response)

      described_class.new(term: "foto", country: "de").fetch

      expect(req.params["country"]).to eq("de")
      expect(req.params["term"]).to eq("foto")
      expect(req.params["clientApplication"]).to eq("Software")
    end

    it "returns an empty array when Apple's hints array is empty" do
      stub_faraday(body: empty_plist_response)

      expect(described_class.new(term: "zzzzzz", country: "us").fetch).to eq([])
    end

    it "returns an empty array on a non-2xx response" do
      stub_faraday(body: "", success: false)

      expect(described_class.new(term: "failure", country: "us").fetch).to eq([])
    end

    it "returns an empty array on a Faraday connection error" do
      conn = instance_double(Faraday::Connection)
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:get).and_raise(Faraday::ConnectionFailed.new("refused"))

      expect(described_class.new(term: "error", country: "us").fetch).to eq([])
    end

    it "returns an empty array on malformed XML" do
      stub_faraday(body: "not xml at all")

      expect(described_class.new(term: "broken", country: "us").fetch).to eq([])
    end

    it "caches results so a second call does not re-hit Apple" do
      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_store)

      stub_faraday(body: plist_response)

      described_class.new(term: "photo", country: "us").fetch

      allow(Faraday).to receive(:new).and_raise("should not be called - cache hit")
      expect(described_class.new(term: "photo", country: "us").fetch).to eq([ "photo editor", "photoshop" ])
    end

    it "de-duplicates hints with identical terms" do
      duplicated = plist_response.sub("<string>photoshop</string>", "<string>photo editor</string>")
      stub_faraday(body: duplicated)

      expect(described_class.new(term: "photo", country: "us").fetch).to eq([ "photo editor" ])
    end
  end
end
