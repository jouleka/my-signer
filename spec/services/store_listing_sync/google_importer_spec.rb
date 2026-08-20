require "rails_helper"

RSpec.describe StoreListingSync::GoogleImporter do
  let(:user) { User.create!(email: "gpimporter@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }
  let(:android_app) { AndroidApp.create!(organization: organization, package_name: "com.test.android", name: "Test") }
  let!(:credential) do
    GooglePlayCredential.create!(
      organization: organization, name: "Test GP",
      service_account_json: '{"type":"service_account","project_id":"test","private_key_id":"key","private_key":"-----BEGIN RSA PRIVATE KEY-----\\nfake\\n-----END RSA PRIVATE KEY-----\\n","client_email":"test@test.iam.gserviceaccount.com","client_id":"123","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token"}',
      active: true
    )
  end

  let(:mock_client) { instance_double(GooglePlay::Client) }
  let(:mock_listings) { instance_double(GooglePlay::Listings) }

  before do
    allow(GooglePlay::Client).to receive(:new).and_return(mock_client)
    allow(GooglePlay::Listings).to receive(:new).and_return(mock_listings)
  end

  describe "#import!" do
    let(:listings_data) do
      [
        { language: "en-US", title: "My Android App", short_description: "Short", full_description: "Full desc" },
        { language: "es-ES", title: "Mi App", short_description: "Corto", full_description: "Desc completa" }
      ]
    end

    let(:mock_screenshots) { instance_double(GooglePlay::Screenshots) }

    before do
      allow(mock_listings).to receive(:list).and_return(listings_data)

      # Stub screenshot sync (best-effort, runs after main import).
      # The importer now opens one edit per-app for all locales' screenshots
      # (vs. one edit per-locale previously), so it needs create/delete stubs.
      allow(GooglePlay::Screenshots).to receive(:new).and_return(mock_screenshots)
      allow(mock_screenshots).to receive(:fetch_current_screenshots).and_return({})
      allow(mock_screenshots).to receive(:fetch_current_screenshots_with_edit).and_return({})
      allow(mock_client).to receive(:create_edit).and_return(double(id: "edit-123"))
      allow(mock_client).to receive(:delete_edit)
    end

    it "creates store listings from Google Play data" do
      importer = described_class.new(organization: organization, android_app: android_app)
      result = importer.import!

      expect(result.size).to eq(2)

      en_listing = android_app.store_listings.find_by(locale: "en-US")
      expect(en_listing.app_name).to eq("My Android App")
      expect(en_listing.short_description).to eq("Short")
      expect(en_listing.description).to eq("Full desc")
      expect(en_listing.sync_status).to eq("synced")
    end

    it "raises without active credential" do
      credential.update!(active: false)
      expect {
        described_class.new(organization: organization, android_app: android_app)
      }.to raise_error("No active Google Play credential")
    end

    context "when Google returns a locale in underscore format" do
      let(:underscore_listings_data) do
        [
          { language: "pt_BR", title: "Meu App", short_description: "Curto", full_description: "Completa" }
        ]
      end

      before do
        allow(mock_listings).to receive(:list).and_return(underscore_listings_data)
      end

      it "normalizes the locale to hyphen format before saving" do
        importer = described_class.new(organization: organization, android_app: android_app)
        importer.import!

        locales = android_app.store_listings.pluck(:locale)
        expect(locales).to include("pt-BR")
        expect(locales).not_to include("pt_BR")
      end

      it "persists the imported content against the normalized locale" do
        importer = described_class.new(organization: organization, android_app: android_app)
        importer.import!

        listing = android_app.store_listings.find_by(locale: "pt-BR")
        expect(listing).not_to be_nil
        expect(listing.app_name).to eq("Meu App")
        expect(listing.short_description).to eq("Curto")
        expect(listing.description).to eq("Completa")
      end
    end
  end
end
