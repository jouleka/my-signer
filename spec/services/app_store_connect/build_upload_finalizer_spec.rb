require "rails_helper"
require "webmock/rspec"

RSpec.describe AppStoreConnect::BuildUploadFinalizer do
  let(:cred)   { create(:app_store_connect_credential) }
  let(:upload) { create(:asc_build_upload, state: "pending", organization: cred.organization) }

  before { allow(AppStoreConnect::JwtMinter).to receive(:for).and_return("stub.jwt") }

  context "happy path" do
    before do
      stub_request(:patch, "https://api.appstoreconnect.apple.com/v1/buildUploadFiles/#{upload.remote_file_id}")
        .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://api.appstoreconnect.apple.com/v1/buildUploads/#{upload.remote_id}")
        .to_return(status: 200, body: {
          data: { attributes: { state: { state: "PROCESSING" } } }
        }.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "marks the row uploaded and stores Apple state" do
      described_class.new(credential: cred, build_upload: upload, checksums: { md5: "a", sha256: "b" }).call
      upload.reload
      expect(upload.state).to eq("uploaded")
      expect(upload.apple_state).to eq("PROCESSING")
      expect(upload.uploaded_at).not_to be_nil
    end

    it "configures explicit read and open timeouts on the Faraday connection (M-9)" do
      connections = []
      original = Faraday.method(:new)
      allow(Faraday).to receive(:new) do |*args, &blk|
        conn = original.call(*args, &blk)
        connections << conn
        conn
      end

      described_class.new(credential: cred, build_upload: upload, checksums: { md5: "a", sha256: "b" }).call

      expect(connections).not_to be_empty
      connections.each do |conn|
        expect(conn.options.timeout).to eq(20)
        expect(conn.options.open_timeout).to eq(20)
      end
    end
  end

  context "Apple returns 409 on duplicate PATCH" do
    before do
      stub_request(:patch, "https://api.appstoreconnect.apple.com/v1/buildUploadFiles/#{upload.remote_file_id}")
        .to_return(status: 409, body: {}.to_json)
      stub_request(:get, "https://api.appstoreconnect.apple.com/v1/buildUploads/#{upload.remote_id}")
        .to_return(status: 200, body: { data: { attributes: { state: { state: "COMPLETE" } } } }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "treats 409 as success (idempotent PATCH)" do
      expect {
        described_class.new(credential: cred, build_upload: upload, checksums: { md5: "a", sha256: "b" }).call
      }.not_to raise_error
      expect(upload.reload.state).to eq("uploaded")
    end
  end
end
