require "rails_helper"

RSpec.describe StoreListingSync::AppleImporter do
  let(:user) { User.create!(email: "importer@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }
  let(:apple_app) { AppleApp.create!(organization: organization, app_store_id: "999", bundle_id: "com.test.app", name: "Test") }
  let!(:credential) do
    AppStoreConnectCredential.create!(
      organization: organization, name: "Test ASC", key_id: "KEYID12345", issuer_id: "ISSUERID-1234-5678-90AB",
      private_key: "-----BEGIN EC PRIVATE KEY-----\nfake\n-----END EC PRIVATE KEY-----", active: true
    )
  end

  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  let(:mock_app_info) { instance_double(AppStoreConnect::AppInfo) }
  let(:mock_versions) { instance_double(AppStoreConnect::Versions) }

  before do
    allow(AppStoreConnect::Client).to receive(:new).and_return(mock_client)
    allow(AppStoreConnect::AppInfo).to receive(:new).and_return(mock_app_info)
    allow(AppStoreConnect::Versions).to receive(:new).and_return(mock_versions)
  end

  describe "#import!" do
    let(:app_info_data) { { "id" => "info123", "attributes" => { "state" => "READY_FOR_DISTRIBUTION" } } }
    let(:app_info_localizations) do
      [
        { "id" => "loc1", "attributes" => { "locale" => "en-US", "name" => "My App", "subtitle" => "Great app" } },
        { "id" => "loc2", "attributes" => { "locale" => "de-DE", "name" => "Meine App", "subtitle" => "Tolle App" } }
      ]
    end
    let(:version_data) { { "id" => "ver123", "attributes" => { "versionString" => "1.0" } } }
    let(:version_localizations) do
      [
        {
          "id" => "vloc1",
          "attributes" => {
            "locale" => "en-US", "description" => "A great app for everyone.",
            "keywords" => "productivity,tools", "whatsNew" => "Bug fixes",
            "promotionalText" => "Try now!", "supportUrl" => "https://support.example.com",
            "marketingUrl" => nil, "privacyPolicyUrl" => "https://privacy.example.com"
          }
        }
      ]
    end

    let(:mock_screenshots) { instance_double(AppStoreConnect::Screenshots) }

    before do
      allow(mock_app_info).to receive(:primary).and_return(app_info_data)
      allow(mock_app_info).to receive(:localizations).and_return(app_info_localizations)
      allow(mock_versions).to receive(:editable_versions).and_return([ version_data ])
      allow(mock_versions).to receive(:localizations).and_return(version_localizations)

      # Stub screenshot sync (best-effort, runs after main import)
      allow(AppStoreConnect::Screenshots).to receive(:new).and_return(mock_screenshots)
      allow(mock_screenshots).to receive(:list_screenshot_sets).and_return([])
    end

    it "creates store listings from ASC data" do
      importer = described_class.new(organization: organization, apple_app: apple_app)
      result = importer.import!

      expect(result).to be_an(Array)
      expect(result.size).to eq(2) # en-US (both sources) and de-DE (app_info only)

      en_listing = apple_app.store_listings.find_by(locale: "en-US")
      expect(en_listing.app_name).to eq("My App")
      expect(en_listing.subtitle).to eq("Great app")
      expect(en_listing.description).to eq("A great app for everyone.")
      expect(en_listing.keywords).to eq("productivity,tools")
      expect(en_listing.sync_status).to eq("synced")
      expect(en_listing.last_synced_at).to be_present
    end

    it "updates existing listings" do
      StoreListing.create!(
        organization: organization, listable: apple_app, locale: "en-US",
        app_name: "Old Name", sync_status: "draft"
      )

      importer = described_class.new(organization: organization, apple_app: apple_app)
      importer.import!

      listing = apple_app.store_listings.find_by(locale: "en-US")
      expect(listing.app_name).to eq("My App")
      expect(listing.sync_status).to eq("synced")
    end

    it "raises without active credential" do
      credential.update!(active: false)
      expect {
        described_class.new(organization: organization, apple_app: apple_app)
      }.to raise_error("No active App Store Connect credential")
    end

    context "when no editable version exists (e.g., live READY_FOR_SALE app)" do
      let(:live_version) {
        { "id" => "ver_live_1",
          "attributes" => { "versionString" => "75", "appStoreState" => "READY_FOR_SALE" } }
      }
      let(:live_version_localizations) do
        [
          {
            "id" => "vloc_live_1",
            "attributes" => {
              "locale" => "en-GB",
              "description" => "British description from live version.",
              "keywords" => "british,keywords",
              "whatsNew" => "What's new in v75",
              "promotionalText" => "Try v75",
              "supportUrl" => "https://support.example.co.uk",
              "marketingUrl" => "https://marketing.example.co.uk"
            }
          }
        ]
      end

      before do
        # editable_versions returns empty (no version is editable)
        allow(mock_versions).to receive(:editable_versions).and_return([])
        # latest_version returns the live READY_FOR_SALE version
        allow(mock_versions).to receive(:latest_version).and_return(live_version)
        # localizations are then fetched for the live version
        allow(mock_versions).to receive(:localizations).with(version_id: "ver_live_1").and_return(live_version_localizations)
      end

      it "falls back to latest_version and imports description/keywords/whats_new" do
        importer = described_class.new(organization: organization, apple_app: apple_app)
        importer.import!

        listing = apple_app.store_listings.find_by(locale: "en-GB")
        expect(listing).not_to be_nil
        expect(listing.description).to eq("British description from live version.")
        expect(listing.keywords).to eq("british,keywords")
        expect(listing.whats_new).to eq("What's new in v75")
        expect(listing.promotional_text).to eq("Try v75")
        expect(listing.support_url).to eq("https://support.example.co.uk")
        expect(listing.marketing_url).to eq("https://marketing.example.co.uk")
      end

      it "calls latest_version exactly once when editable_versions is empty" do
        expect(mock_versions).to receive(:latest_version).with(app_id: apple_app.app_store_id).once.and_return(live_version)

        importer = described_class.new(organization: organization, apple_app: apple_app)
        importer.import!
      end

      it "does not call latest_version when an editable version is available" do
        editable = { "id" => "ver_editable", "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION" } }
        allow(mock_versions).to receive(:editable_versions).and_return([ editable ])
        allow(mock_versions).to receive(:localizations).with(version_id: "ver_editable").and_return([])
        expect(mock_versions).not_to receive(:latest_version)

        importer = described_class.new(organization: organization, apple_app: apple_app)
        importer.import!
      end

      it "imports nothing version-level when both editable and latest_version are nil" do
        allow(mock_versions).to receive(:latest_version).and_return(nil)

        importer = described_class.new(organization: organization, apple_app: apple_app)
        result = importer.import!

        # App-info localizations still create listings (en-US, de-DE) but with no version data
        en = apple_app.store_listings.find_by(locale: "en-US")
        expect(en).not_to be_nil
        expect(en.description).to be_nil
        expect(en.whats_new).to be_nil
      end
    end
  end
end
