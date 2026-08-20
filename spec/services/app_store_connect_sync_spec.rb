require "rails_helper"

RSpec.describe AppStoreConnect::Sync do
  let(:org) { Organization.create!(name: "Org", owner: User.create!(email: "a@b.com", password: "QwErTy!12345$", confirmed_at: Time.current)) }
  let(:ec_key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:cred) do
    AppStoreConnectCredential.create!(
      organization: org,
      name: "Apple",
      key_id: "KEY12345",
      issuer_id: "11111111-1111-1111-1111-111111111111",
      private_key: ec_key.to_pem,
      active: true
    )
  end

  before { cred }

  it "upserts devices/certs/profiles and marks success" do
    client = instance_double(AppStoreConnect::Client)
    allow(AppStoreConnect::Client).to receive(:new).and_return(client)

    # Stub pagination callbacks for all sync methods
    allow(client).to receive(:paginate).with("bundleIds", params: { limit: 200 }).and_yield({ "data" => [] })
    allow(client).to receive(:paginate).with("certificates", params: { limit: 200 }).and_yield({ "data"=>[ { "id"=>"C1", "attributes"=>{ "name"=>"Dev", "certificateType"=>"IOS_DEVELOPMENT", "serialNumber"=>"S", "platform"=>"IOS", "status"=>"ACTIVE", "expirationDate"=>Time.now.iso8601 } } ] })
    allow(client).to receive(:paginate).with("devices", params: { limit: 200 }).and_yield({ "data"=>[ { "id"=>"D1", "attributes"=>{ "name"=>"John's iPhone", "udid"=>"udid", "platform"=>"IOS", "deviceClass"=>"IPHONE", "status"=>"ENABLED", "addedDate"=>Time.now.iso8601 } } ] })
    allow(client).to receive(:paginate).with("profiles", params: { limit: 200, include: "bundleId" }).and_yield({ "data"=>[ { "id"=>"P1", "attributes"=>{ "name"=>"DevProfile", "uuid"=>"uuid", "profileType"=>"IOS_APP_DEVELOPMENT", "profileState"=>"ACTIVE", "platform"=>"IOS", "expirationDate"=>Time.now.iso8601 }, "relationships"=>{ "bundleId"=>{ "data"=>{ "id"=>"BID1" } } } } ] })
    allow(client).to receive(:paginate).with("merchantIds", params: { limit: 200 }).and_yield({ "data" => [] })

    # Stub apps and related sync calls
    allow(client).to receive(:paginate).with("apps", params: { limit: 200 }).and_yield({ "data" => [] })

    expect {
      described_class.new(organization: org).call
    }.to change { AppleDevice.count }.by(1)
     .and change { AppleCertificate.count }.by(1)
     .and change { AppleProvisioningProfile.count }.by(1)

    cred.reload
    expect(cred.last_sync_status).to eq("ok")
    expect(cred.last_synced_at).to be_present
  end

  describe "validation_errors integration" do
    let(:client) { instance_double(AppStoreConnect::Client) }
    let(:apple_app) do
      AppleApp.create!(
        organization: org,
        app_store_id: "1000000001",
        bundle_id: "com.example.test",
        name: "Test App"
      )
    end
    let(:versions_service) { instance_double(AppStoreConnect::Versions) }

    before do
      apple_app
      allow(AppStoreConnect::Client).to receive(:new).and_return(client)

      # Stub everything other than versions to keep these tests focused.
      allow(client).to receive(:paginate).with("bundleIds", params: { limit: 200 }).and_yield({ "data" => [] })
      allow(client).to receive(:paginate).with("certificates", params: { limit: 200 }).and_yield({ "data" => [] })
      allow(client).to receive(:paginate).with("devices", params: { limit: 200 }).and_yield({ "data" => [] })
      allow(client).to receive(:paginate).with("profiles", params: { limit: 200, include: "bundleId" }).and_yield({ "data" => [] })
      allow(client).to receive(:paginate).with("merchantIds", params: { limit: 200 }).and_yield({ "data" => [] })

      # Apps endpoint must include our existing app's id so sync_apps doesn't delete it.
      allow(client).to receive(:paginate).with("apps", params: { limit: 200 }).and_yield({
        "data" => [
          {
            "id" => apple_app.app_store_id,
            "attributes" => {
              "bundleId" => apple_app.bundle_id,
              "name" => apple_app.name,
              "sku" => nil
            }
          }
        ]
      })

      # Builds endpoint - return empty.
      allow(client).to receive(:paginate).with(
        "builds",
        params: { "filter[app]" => apple_app.app_store_id, limit: 100, include: "preReleaseVersion" }
      ).and_yield({ "data" => [] })

      # Testflight endpoint - return empty.
      allow(client).to receive(:paginate).with(
        "/v1/apps/#{apple_app.app_store_id}/betaGroups",
        anything
      ).and_yield({ "data" => [] })

      # Replace AppStoreConnect::Versions with a fake instance whose `list` yields
      # both an editable and a non-editable version. We then control
      # `validation_errors` per-test via further allow/expect statements.
      allow(AppStoreConnect::Versions).to receive(:new).with(client).and_return(versions_service)
      allow(versions_service).to receive(:list).with(app_id: apple_app.app_store_id, limit: 50).and_yield({
        "data" => [
          {
            "id" => "asv-editable",
            "attributes" => {
              "versionString" => "1.2.0",
              "platform" => "IOS",
              "appStoreState" => "PREPARE_FOR_SUBMISSION"
            }
          },
          {
            "id" => "asv-live",
            "attributes" => {
              "versionString" => "1.1.0",
              "platform" => "IOS",
              "appStoreState" => "READY_FOR_SALE"
            }
          },
          {
            "id" => "asv-distributing",
            "attributes" => {
              "versionString" => "1.0.0",
              "platform" => "IOS",
              "appStoreState" => "PROCESSING_FOR_DISTRIBUTION"
            }
          }
        ]
      })
    end

    it "calls validation_errors only for editable versions, not for shipped/processing ones" do
      expect(versions_service).to receive(:validation_errors).with(version_id: "asv-editable").once.and_return([])
      expect(versions_service).not_to receive(:validation_errors).with(version_id: "asv-live")
      expect(versions_service).not_to receive(:validation_errors).with(version_id: "asv-distributing")

      described_class.new(organization: org).call
    end

    it "normalizes string-shaped errors and persists them on the editable version" do
      raw_errors = [
        "MISSING_METADATA: Description is required",
        "INVALID_BINARY: Binary failed verification"
      ]
      allow(versions_service).to receive(:validation_errors).with(version_id: "asv-editable").and_return(raw_errors)

      described_class.new(organization: org).call

      version = AppStoreVersion.find_by!(version_id: "asv-editable")
      expect(version.issues).to be_an(Array)
      expect(version.issues.length).to eq(2)
      expect(version.issues.first).to include(
        "code" => "MISSING_METADATA",
        "detail" => "Description is required"
      )
      expect(version.issues.first["raw"]).to eq("MISSING_METADATA: Description is required")
      expect(version.issues.last).to include(
        "code" => "INVALID_BINARY",
        "detail" => "Binary failed verification"
      )
      expect(version.issues_synced_at).to be_present
    end

    it "stores an empty array and stamps issues_synced_at when validation passes cleanly" do
      allow(versions_service).to receive(:validation_errors).with(version_id: "asv-editable").and_return([])

      described_class.new(organization: org).call

      version = AppStoreVersion.find_by!(version_id: "asv-editable")
      expect(version.issues).to eq([])
      expect(version.issues_synced_at).to be_present
    end

    it "logs and continues when validation_errors raises for one version" do
      allow(versions_service).to receive(:validation_errors).with(version_id: "asv-editable").and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:warn).and_call_original

      expect {
        described_class.new(organization: org).call
      }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).with(/validation_errors failed for version .* StandardError - boom/)

      cred.reload
      expect(cred.last_sync_status).to eq("ok")

      version = AppStoreVersion.find_by!(version_id: "asv-editable")
      expect(version.issues).to eq([])
      expect(version.issues_synced_at).to be_nil
    end

    it "is idempotent: a second sync replaces the issues array rather than appending" do
      first_run = [ "MISSING_METADATA: Description is required" ]
      second_run = [ "INVALID_BINARY: Binary failed verification" ]
      allow(versions_service).to receive(:validation_errors).with(version_id: "asv-editable").and_return(first_run, second_run)

      described_class.new(organization: org).call
      version = AppStoreVersion.find_by!(version_id: "asv-editable")
      expect(version.issues.map { |i| i["code"] }).to eq([ "MISSING_METADATA" ])

      described_class.new(organization: org).call
      version.reload
      expect(version.issues.map { |i| i["code"] }).to eq([ "INVALID_BINARY" ])
      expect(version.issues.length).to eq(1)
    end

    it "defaults the issues column to an empty array on a new AppStoreVersion" do
      expect(AppStoreVersion.new.issues).to eq([])
    end
  end
end
