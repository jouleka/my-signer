require "rails_helper"

RSpec.describe GooglePlay::Sync do
  let(:user) { User.create!(email: "google-play@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "My Droid Org", owner: user) }
  let!(:android_app) { AndroidApp.create!(organization: organization, package_name: "com.example.syncdemo", name: "Sync Demo") }
  let(:service_json) do
    {
      "type" => "service_account",
      "project_id" => "demo",
      "private_key_id" => "keyid",
      "private_key" => "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
      "client_email" => "svc@example.com",
      "client_id" => "client-id",
      "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
      "token_uri" => "https://oauth2.googleapis.com/token"
    }.to_json
  end
  let!(:credential) do
    GooglePlayCredential.create!(
      organization: organization,
      name: "Primary",
      service_account_json: service_json,
      developer_account_id: "12345",
      active: true
    )
  end

  let(:client) { instance_double(GooglePlay::Client) }
  let(:edit) { double("Edit", id: "edit-1") }

  before do
    allow(GooglePlay::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_edit).and_return(edit)
    allow(client).to receive(:commit_edit)
    allow(client).to receive(:delete_edit)

    details = double("Details", default_language: "en-US")
    allow(details).to receive(:to_json).and_return({ defaultLanguage: "en-US" }.to_json)
    allow(client).to receive(:fetch_app_details).and_return(details)

    listing = double("Listing")
    allow(listing).to receive(:to_json).and_return({ language: "en-US", title: "Sync Demo App" }.to_json)
    allow(client).to receive(:list_app_listings).and_return(double("ListingsResponse", listings: [ listing ]))

    release = double("Release",
                     name: "1.0.0",
                     status: "completed",
                     version_codes: [ "100" ],
                     versionCodes: [ "100" ])
    track_payload = { track: "internal", releases: [ { versionCodes: [ "100" ] } ] }
    track = double("Track", track: "internal", releases: [ release ])
    allow(track).to receive(:to_json).and_return(track_payload.to_json)
    allow(client).to receive(:list_tracks).and_return(double("TracksResponse", tracks: [ track ]))

    bundle_payload = {
      "versionCode" => "100",
      "versionName" => "1.0.0",
      "size" => 2048,
      "binary" => { "sha1" => "abc123", "sha256" => "def456" },
      "minSdkVersion" => "21",
      "targetSdkVersion" => "34",
      "nativeCode" => %w[arm64-v8a],
      "createTime" => 1.day.ago.iso8601
    }
    bundle = double("Bundle")
    allow(bundle).to receive(:to_json).and_return(bundle_payload.to_json)
    allow(client).to receive(:list_bundles).and_return(double("BundlesResponse", bundles: [ bundle ]))

    allow(client).to receive(:list_apks).and_return(double("ApksResponse", apks: []))
  end

  it "syncs tracks and builds into android_builds" do
    expect {
      described_class.new(organization: organization).sync_all!(package_names: [ android_app.package_name ])
    }.to change(AndroidBuild, :count).by(1)
     .and change(AndroidTrack, :count).by(1)

    build = AndroidBuild.find_by(version_code: "100")
    expect(build).to have_attributes(
      organization_id: organization.id,
      android_app_id: android_app.id,
      version_name: "1.0.0",
      binary_sha1: "abc123",
      binary_sha256: "def456",
      status: "completed"
    )
    expect(build.native_code).to include("arm64-v8a")
    expect(build.file_size_bytes).to eq(2048)
    expect(build.raw_json["artifact_type"]).to eq("bundle")
  end
end
