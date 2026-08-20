require "rails_helper"
require "webmock/rspec"

RSpec.describe AppStoreConnect::BuildUploadStatusChecker do
  let(:cred)   { create(:app_store_connect_credential) }
  let(:upload) { create(:asc_build_upload, state: "uploaded", apple_state: "PROCESSING", organization: cred.organization) }

  before { allow(AppStoreConnect::JwtMinter).to receive(:for).and_return("stub.jwt") }

  it "refreshes apple_state from Apple when non-terminal" do
    stub_request(:get, "https://api.appstoreconnect.apple.com/v1/buildUploads/#{upload.remote_id}")
      .to_return(status: 200, body: { data: { attributes: { state: { state: "COMPLETE" } } } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    described_class.new(credential: cred, build_upload: upload).call
    expect(upload.reload.apple_state).to eq("COMPLETE")
  end

  it "does NOT call Apple if apple_state is already terminal (COMPLETE)" do
    upload.update!(apple_state: "COMPLETE")
    described_class.new(credential: cred, build_upload: upload).call
    expect(WebMock).not_to have_requested(:get, %r{/v1/buildUploads/})
  end

  it "configures explicit read and open timeouts on the Faraday connection (M-9)" do
    stub_request(:get, "https://api.appstoreconnect.apple.com/v1/buildUploads/#{upload.remote_id}")
      .to_return(status: 200, body: { data: { attributes: { state: { state: "COMPLETE" } } } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    connections = []
    original = Faraday.method(:new)
    allow(Faraday).to receive(:new) do |*args, &blk|
      conn = original.call(*args, &blk)
      connections << conn
      conn
    end

    described_class.new(credential: cred, build_upload: upload).call

    expect(connections).not_to be_empty
    connections.each do |conn|
      expect(conn.options.timeout).to eq(20)
      expect(conn.options.open_timeout).to eq(20)
    end
  end
end
