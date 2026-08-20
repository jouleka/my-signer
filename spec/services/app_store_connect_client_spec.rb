require "rails_helper"

RSpec.describe AppStoreConnect::Client do
  let(:org) { Organization.create!(name: "Test Org", owner: User.create!(email: "u@example.com", password: "QwErTy!12345$", confirmed_at: Time.current)) }
  let(:ec_key) {
    OpenSSL::PKey::EC.generate("prime256v1")
  }
  let(:credential) do
    AppStoreConnectCredential.create!(
      organization: org,
      name: "Apple",
      key_id: "KEY12345",
      issuer_id: "11111111-1111-1111-1111-111111111111",
      private_key: ec_key.to_pem,
      active: true
    )
  end

  it "builds Authorization header with ES256 JWT" do
    stub = Faraday::Adapter::Test::Stubs.new
    conn = Faraday.new { |f| f.adapter :test, stub }
    allow(Faraday).to receive(:new).and_return(conn)

    client = described_class.new(credential: credential)

    stub.get("/v1/certificates") do |env|
      auth = env.request_headers["Authorization"]
      expect(auth).to start_with("Bearer ")
      [ 200, { "Content-Type"=>"application/json" }, { data: [] }.to_json ]
    end

    body = client.get("/v1/certificates")
    expect(body).to eq({ "data"=>[] })
  end

  it "emits an asc_credential_used audit event on the dominant request path (M-10)" do
    # #jwt delegates to the single JwtMinter signer, so EVERY Apple API call
    # funnels through the audited mint path. Previously Client#jwt had its own
    # inline signer and emitted NO audit event.
    stub = Faraday::Adapter::Test::Stubs.new
    conn = Faraday.new { |f| f.adapter :test, stub }
    allow(Faraday).to receive(:new).and_return(conn)

    client = described_class.new(credential: credential)
    stub.get("/v1/certificates") { [ 200, { "Content-Type"=>"application/json" }, { data: [] }.to_json ] }

    expect {
      client.get("/v1/certificates")
    }.to change(
      AuditEvent.where(organization: credential.organization, action: "asc_credential_used"), :count
    ).by(1)
  end

  it "Client#jwt produces a valid ES256 token decodable with the credential key" do
    client = described_class.new(credential: credential)
    token = client.send(:jwt)
    payload, header = JWT.decode(token, ec_key, true, algorithm: "ES256")
    expect(header["alg"]).to eq("ES256")
    expect(header["kid"]).to eq("KEY12345")
    expect(payload["aud"]).to eq("appstoreconnect-v1")
    expect(payload["iss"]).to eq("11111111-1111-1111-1111-111111111111")
  end
end
