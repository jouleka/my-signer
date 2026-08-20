require "rails_helper"
require "webmock/rspec"

RSpec.describe AppStoreConnect::BuildUploadCreator do
  let(:org) { create(:organization) }
  let(:user) { org.owner }
  let(:apple_app) { create(:apple_app, organization: org, app_store_id: "6757942957") }
  let(:cred) { create(:app_store_connect_credential, organization: org) }

  let(:params) do
    {
      apple_app: apple_app,
      cf_bundle_version: "123",
      cf_bundle_short_version_string: "1.2.3",
      platform: "IOS",
      file_name: "app.ipa",
      file_size: 10_000_000,
      user: user
    }
  end

  before do
    allow(AppStoreConnect::JwtMinter).to receive(:for).with(cred).and_return("stub.jwt.token")
  end

  context "happy path" do
    before do
      stub_request(:post, "https://api.appstoreconnect.apple.com/v1/buildUploads")
        .to_return(status: 201, body: {
          data: { id: "remote-upload-id-1", type: "buildUploads", attributes: { state: { state: "IN_PROGRESS" } } }
        }.to_json, headers: { "Content-Type" => "application/json" })

      stub_request(:post, "https://api.appstoreconnect.apple.com/v1/buildUploadFiles")
        .to_return(status: 201, body: {
          data: {
            id: "remote-file-id-1",
            type: "buildUploadFiles",
            attributes: {
              uploadOperations: [
                { method: "PUT", url: "https://s3.x/chunk1", offset: 0, length: 10_000_000, requestHeaders: [] }
              ]
            }
          }
        }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "creates a build upload + returns operations" do
      result = described_class.new(credential: cred, params: params).call
      expect(result[:build_upload].state).to eq("pending")
      expect(result[:build_upload].remote_id).to eq("remote-upload-id-1")
      expect(result[:build_upload].remote_file_id).to eq("remote-file-id-1")
      expect(result[:upload_operations]).to be_an(Array).and have_attributes(size: 1)
    end

    it "persists an AscBuildUpload row" do
      expect { described_class.new(credential: cred, params: params).call }
        .to change(AscBuildUpload, :count).by(1)
    end

    it "configures explicit read and open timeouts on the Faraday connection (M-9)" do
      connections = []
      original = Faraday.method(:new)
      allow(Faraday).to receive(:new) do |*args, &blk|
        conn = original.call(*args, &blk)
        connections << conn
        conn
      end

      described_class.new(credential: cred, params: params).call

      expect(connections).not_to be_empty
      connections.each do |conn|
        expect(conn.options.timeout).to eq(20)
        expect(conn.options.open_timeout).to eq(20)
      end
    end
  end

  context "Apple returns 409 on invalid app relationship" do
    before do
      stub_request(:post, "https://api.appstoreconnect.apple.com/v1/buildUploads")
        .to_return(status: 409, body: {
          errors: [ { code: "ENTITY_ERROR.RELATIONSHIP.INVALID", detail: "bad app id", source: { pointer: "/data/relationships/app/data/id" } } ]
        }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "raises BuildUploadCreator::AppleError with sanitized detail" do
      expect { described_class.new(credential: cred, params: params).call }
        .to raise_error(AppStoreConnect::BuildUploadCreator::AppleError)
    end

    it "does NOT persist a row on Apple error" do
      expect { described_class.new(credential: cred, params: params).call rescue nil }
        .not_to change(AscBuildUpload, :count)
    end
  end

  context "duplicate pending row" do
    before { create(:asc_build_upload, organization: org, apple_app: apple_app, cf_bundle_version: "123", state: "pending") }

    it "raises DuplicatePending" do
      expect { described_class.new(credential: cred, params: params).call }
        .to raise_error(AppStoreConnect::BuildUploadCreator::DuplicatePending)
    end
  end
end
