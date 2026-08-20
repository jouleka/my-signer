require "rails_helper"
require "ostruct"

RSpec.describe GooglePlay::Listings do
  let(:credential) { instance_double("GooglePlayCredential", service_account_json: '{"type":"service_account"}', active?: true) }
  let(:mock_service) { instance_double("Google::Apis::AndroidpublisherV3::AndroidPublisherService") }
  let(:mock_auth) { instance_double("Google::Auth::ServiceAccountCredentials") }
  let(:client) { GooglePlay::Client.new(credential: credential) }
  let(:listings_service) { described_class.new(client) }
  let(:package_name) { "com.example.app" }

  before do
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(mock_auth)
    allow(Google::Apis::AndroidpublisherV3::AndroidPublisherService).to receive(:new).and_return(mock_service)
    allow(mock_service).to receive(:authorization=)
    allow(mock_service).to receive(:client_options).and_return(OpenStruct.new(open_timeout_sec: nil, read_timeout_sec: nil))
    allow(mock_service).to receive(:request_options).and_return(OpenStruct.new(retries: nil))
  end

  describe "#list" do
    it "returns all locale listings" do
      edit = OpenStruct.new(id: "edit123")
      listing1 = OpenStruct.new(language: "en-US", title: "My App", short_description: "Short", full_description: "Full")
      listing2 = OpenStruct.new(language: "de-DE", title: "Meine App", short_description: "Kurz", full_description: "Voll")
      response = OpenStruct.new(listings: [ listing1, listing2 ])

      allow(mock_service).to receive(:insert_edit).and_return(edit)
      allow(mock_service).to receive(:list_edit_listings).and_return(response)
      allow(mock_service).to receive(:delete_edit)

      result = listings_service.list(package_name)

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:language]).to eq("en-US")
      expect(result.first[:title]).to eq("My App")
      expect(result.last[:language]).to eq("de-DE")
    end

    it "cleans up edit on failure" do
      edit = OpenStruct.new(id: "edit123")
      allow(mock_service).to receive(:insert_edit).and_return(edit)
      allow(mock_service).to receive(:list_edit_listings).and_raise(StandardError, "API error")
      allow(mock_service).to receive(:delete_edit)

      expect { listings_service.list(package_name) }.to raise_error(StandardError, "API error")
    end
  end

  describe "#update" do
    it "updates a listing for a specific locale" do
      edit = OpenStruct.new(id: "edit123")
      updated = OpenStruct.new(language: "en-US", title: "Updated App", short_description: "New", full_description: "Updated desc")

      allow(mock_service).to receive(:insert_edit).and_return(edit)
      allow(mock_service).to receive(:update_edit_listing).and_return(updated)
      allow(mock_service).to receive(:commit_edit)

      result = listings_service.update(
        package_name,
        locale: "en-US",
        title: "Updated App",
        short_description: "New",
        full_description: "Updated desc"
      )

      expect(result[:title]).to eq("Updated App")
      expect(result[:language]).to eq("en-US")
    end
  end
end
