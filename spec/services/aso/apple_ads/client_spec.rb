require "rails_helper"
require "webmock/rspec"

RSpec.describe Aso::AppleAds::Client do
  let(:credential) { create(:apple_ads_credential) }
  let(:oauth_body) { File.read(Rails.root.join("spec/fixtures/aso/apple_ads_oauth_success.json")) }
  let(:recs_body)  { File.read(Rails.root.join("spec/fixtures/aso/apple_ads_recommendations_response.json")) }

  before do
    Rails.cache.clear
    # Use a real cache so fetch behavior is testable
    @memory_store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(@memory_store)
  end

  subject(:client) { described_class.new(credential: credential) }

  describe "#access_token" do
    it "mints an ES256 JWT, exchanges for access_token, caches it" do
      stub_oauth = stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 200, body: oauth_body)
      expect(client.access_token).to eq("test_access_token_xyz")

      # Second call uses cache
      client.access_token
      expect(stub_oauth).to have_been_requested.once
    end

    it "raises CredentialsInvalid on 401 from OAuth" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 401, body: '{"error":"invalid_client"}')
      expect { client.access_token }.to raise_error(Aso::AppleAds::CredentialsInvalid)
    end

    it "raises CredentialsInvalid on 403" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 403, body: '{"error":"forbidden"}')
      expect { client.access_token }.to raise_error(Aso::AppleAds::CredentialsInvalid)
    end

    it "raises RateLimited on 429" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 429)
      expect { client.access_token }.to raise_error(Aso::AppleAds::RateLimited)
    end

    it "raises TransientError on 500" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 500)
      expect { client.access_token }.to raise_error(Aso::AppleAds::TransientError)
    end

    it "sends correct JWT payload claims (iss=sub=client_id, aud=appleid)" do
      captured = nil
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 200, body: oauth_body)
        .with { |req| captured = req.body; true }

      client.access_token

      params = URI.decode_www_form(captured).to_h
      jwt_str = params["client_assertion"]
      key_obj = OpenSSL::PKey.read(credential.private_key_pem)
      payload, header = JWT.decode(jwt_str, key_obj.public_key, true, algorithm: "ES256")

      expect(payload["iss"]).to eq(credential.client_id)
      expect(payload["sub"]).to eq(credential.client_id)
      expect(payload["aud"]).to eq("https://appleid.apple.com")
      expect(payload["iat"]).to be_a(Integer)
      expect(payload["exp"]).to be_a(Integer)
      expect(header["kid"]).to eq(credential.key_id)
      expect(header["alg"]).to eq("ES256")

      expect(params["grant_type"]).to eq("client_credentials")
      expect(params["client_id"]).to eq(credential.client_id)
      expect(params["client_assertion_type"]).to eq("urn:ietf:params:oauth:client-assertion-type:jwt-bearer")
      expect(params["scope"]).to eq("searchadsorg")
    end

    it "caches the client_assertion JWT separately from access_token" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 200, body: oauth_body)

      client.access_token
      # Purge access_token only; the JWT should still be cached
      Rails.cache.delete("aso/apple_ads/access_token/#{credential.id}")
      expect(Rails.cache.read("aso/apple_ads/assertion/#{credential.id}")).to be_present
    end

    it "stores the access_token and client_assertion ENCRYPTED at rest (M-5)" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 200, body: oauth_body)

      token = client.access_token
      expect(token).to eq("test_access_token_xyz")

      raw_access = Rails.cache.read("aso/apple_ads/access_token/#{credential.id}")
      raw_assertion = Rails.cache.read("aso/apple_ads/assertion/#{credential.id}")

      # The plaintext access token must not be present in the stored blob.
      expect(raw_access).to be_a(String)
      expect(raw_access).not_to include("test_access_token_xyz")
      # The assertion blob must not look like a JWT (3 base64url segments).
      expect(raw_assertion).to be_a(String)
      expect(raw_assertion).not_to match(/\A[\w-]+\.[\w-]+\.[\w-]+\z/)

      # EncryptedTokenCache recovers the originals.
      expect(EncryptedTokenCache.read("aso/apple_ads/access_token/#{credential.id}"))
        .to eq("test_access_token_xyz")
      assertion = EncryptedTokenCache.read("aso/apple_ads/assertion/#{credential.id}")
      expect(assertion).to match(/\A[\w-]+\.[\w-]+\.[\w-]+\z/)
    end
  end

  describe "#recommended_keywords" do
    before do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token").to_return(status: 200, body: oauth_body)
      stub_request(:post, %r{/api/v5/campaigns$}).to_return(status: 200, body: '{"data":{"id":123}}')
      stub_request(:post, %r{/api/v5/campaigns/123/adgroups$}).to_return(status: 200, body: '{"data":{"id":456}}')
      stub_request(:get, %r{/api/v5/campaigns/123/adgroups/456/recommendations/keywords})
        .to_return(status: 200, body: recs_body)
    end

    it "returns normalized keyword records" do
      result = client.recommended_keywords(app_store_id: "1149994032")
      expect(result).to include(
        a_hash_including(keyword: "photo editor", search_popularity: 85, bid_amount_micros: 1_500_000),
        a_hash_including(keyword: "photo collage", search_popularity: 62, bid_amount_micros: 900_000),
        a_hash_including(keyword: "photoshop",     search_popularity: 78, bid_amount_micros: 2_100_000)
      )
    end

    it "sends Authorization Bearer + X-AP-Context headers" do
      client.recommended_keywords(app_store_id: "1149994032")
      expect(WebMock).to have_requested(:get, %r{recommendations/keywords})
        .with(headers: {
          "Authorization" => "Bearer test_access_token_xyz",
          "X-AP-Context"  => "orgId=#{credential.team_id}"
        })
    end

    it "reuses cached campaign+adgroup on second call" do
      2.times { client.recommended_keywords(app_store_id: "1149994032") }
      expect(WebMock).to have_requested(:post, %r{/api/v5/campaigns$}).once
      expect(WebMock).to have_requested(:post, %r{adgroups$}).once
      expect(WebMock).to have_requested(:get, %r{recommendations/keywords}).twice
    end

    it "raises CredentialsInvalid if API returns 401" do
      stub_request(:get, %r{recommendations/keywords}).to_return(status: 401)
      expect { client.recommended_keywords(app_store_id: "1149994032") }
        .to raise_error(Aso::AppleAds::CredentialsInvalid)
    end

    it "handles missing bid_amount gracefully" do
      body_no_bid = { "data" => { "keywords" => [ { "text" => "x", "searchPopularity" => 50 } ] } }.to_json
      stub_request(:get, %r{recommendations/keywords}).to_return(status: 200, body: body_no_bid)
      result = client.recommended_keywords(app_store_id: "1149994032")
      expect(result.first[:bid_amount_micros]).to be_nil
    end
  end

  describe "token cache purge on credential destroy" do
    it "deletes cached access_token and assertion when credential is destroyed" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token").to_return(status: 200, body: oauth_body)
      client.access_token
      access_key = "aso/apple_ads/access_token/#{credential.id}"
      assertion_key = "aso/apple_ads/assertion/#{credential.id}"
      expect(Rails.cache.read(access_key)).to be_present
      expect(Rails.cache.read(assertion_key)).to be_present

      credential.destroy!

      expect(Rails.cache.read(access_key)).to be_nil
      expect(Rails.cache.read(assertion_key)).to be_nil
    end
  end

  describe "audit emission on JWT mint cache miss (mysigner-30 follow-up)" do
    it "emits an apple_ads_credential_used AuditEvent on JWT cache miss" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 200, body: oauth_body)

      expect {
        client.access_token
      }.to change(AuditEvent.where(organization: credential.organization, action: "apple_ads_credential_used"), :count).by(1)

      event = AuditEvent.where(organization: credential.organization, action: "apple_ads_credential_used").last
      expect(event.actor).to be_nil
      expect(event.metadata).to include(
        "credential_id" => credential.id,
        "client_id"     => credential.client_id,
        "cache_miss"    => true
      )
    end

    it "does NOT emit when the assertion JWT is still cached" do
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 200, body: oauth_body)
      client.access_token # warm both caches

      # Expire only the short-lived access_token but keep the long-lived
      # assertion JWT. Second access_token fetch reuses the cached
      # assertion — no fresh mint, no audit event.
      Rails.cache.delete("aso/apple_ads/access_token/#{credential.id}")
      stub_request(:post, "https://appleid.apple.com/auth/oauth2/token")
        .to_return(status: 200, body: oauth_body)

      expect {
        client.access_token
      }.not_to change(AuditEvent.where(action: "apple_ads_credential_used"), :count)
    end
  end
end
