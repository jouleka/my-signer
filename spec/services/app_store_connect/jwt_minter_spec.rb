require "rails_helper"

RSpec.describe AppStoreConnect::JwtMinter do
  let(:ec_key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:pem)    { ec_key.to_pem }
  let(:cred)   { create(:app_store_connect_credential, private_key: pem, key_id: "ABC12345", issuer_id: "11111111-2222-3333-4444-555555555555") }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  it "mints an ES256 JWT with ASC claims" do
    jwt = described_class.for(cred)
    decoded, headers = JWT.decode(jwt, ec_key, true, algorithm: "ES256")
    expect(headers["alg"]).to eq("ES256")
    expect(headers["kid"]).to eq("ABC12345")
    expect(decoded["iss"]).to eq("11111111-2222-3333-4444-555555555555")
    expect(decoded["aud"]).to eq("appstoreconnect-v1")
    expect(decoded["exp"] - decoded["iat"]).to be_between(13 * 60, 16 * 60)
  end

  it "caches and returns the same JWT on repeated calls" do
    first  = described_class.for(cred)
    second = described_class.for(cred)
    expect(first).to eq(second)
  end

  it "stores the JWT ENCRYPTED at rest in the cache (M-5)" do
    jwt = described_class.for(cred)
    raw = Rails.cache.read("asc_jwt:#{cred.id}")
    # The cache blob must NOT be the plaintext JWT.
    expect(raw).to be_present
    expect(raw).not_to eq(jwt)
    expect(raw).not_to include(jwt)
    # And EncryptedTokenCache must be able to recover the original token.
    expect(EncryptedTokenCache.read("asc_jwt:#{cred.id}")).to eq(jwt)
  end

  describe "EC key guard (info finding)" do
    it "raises a clear error when the private key is not an EC key" do
      rsa_pem = OpenSSL::PKey::RSA.generate(2048).to_pem
      bad_cred = create(:app_store_connect_credential, private_key: rsa_pem)
      expect { described_class.for(bad_cred) }
        .to raise_error(/Private key must be EC for ES256/)
    end
  end

  describe "audit emission on cache miss (mysigner-30 follow-up)" do
    it "emits an asc_credential_used AuditEvent on first call (cache miss)" do
      # WHY: forensic visibility into credential USE, not just credential read.
      # Per-cache-miss granularity = ~5x/hour per credential — enough trail
      # to reconstruct "when did the leaked credential sign things?" without
      # flooding the audit table on every controller hit within the 13-min
      # JWT cache window.
      expect {
        described_class.for(cred)
      }.to change(AuditEvent.where(organization: cred.organization, action: "asc_credential_used"), :count).by(1)

      event = AuditEvent.where(organization: cred.organization, action: "asc_credential_used").last
      expect(event.actor).to be_nil # server-side mint; no human actor
      expect(event.metadata).to include(
        "credential_id" => cred.id,
        "key_id"        => cred.key_id,
        "cache_miss"    => true
      )
    end

    it "does NOT emit a fresh event on cache hits" do
      described_class.for(cred) # warm the cache
      expect {
        described_class.for(cred)
      }.not_to change(AuditEvent.where(action: "asc_credential_used"), :count)
    end
  end
end
