require "rails_helper"

RSpec.describe GooglePlay::TokenMinter do
  let(:sa_json) do
    {
      type: "service_account",
      project_id: "test-proj",
      private_key_id: "abc123",
      private_key: "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n",
      client_email: "publisher@test-proj.iam.gserviceaccount.com",
      client_id: "12345"
    }.to_json
  end
  let(:credential) { create(:google_play_credential, service_account_json: sa_json) }

  describe ".mint" do
    let(:stubbed_creds) do
      instance_double(
        Google::Auth::ServiceAccountCredentials,
        access_token: "ya29.FAKE",
        expires_at:   Time.now + 3600
      ).tap { |d| allow(d).to receive(:fetch_access_token!).and_return({ "access_token" => "ya29.FAKE", "expires_in" => 3600 }) }
    end

    before do
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(stubbed_creds)
      @store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(@store)
    end

    it "returns access_token + expires_at + email" do
      result = described_class.mint(credential)
      expect(result[:access_token]).to eq("ya29.FAKE")
      expect(result[:expires_at]).to be_within(2.seconds).of(Time.now + 3600)
      expect(result[:client_email]).to eq("publisher@test-proj.iam.gserviceaccount.com")
    end

    it "caches the minted token" do
      described_class.mint(credential)
      described_class.mint(credential)
      expect(Google::Auth::ServiceAccountCredentials).to have_received(:make_creds).once
    end

    it "reports cache_hit correctly" do
      first  = described_class.mint(credential)
      second = described_class.mint(credential)
      expect(first[:cache_hit]).to eq(false)
      expect(second[:cache_hit]).to eq(true)
    end

    it "stores the access token ENCRYPTED at rest in the cache (M-5)" do
      described_class.mint(credential)
      raw = @store.read("gp_access_token:#{credential.id}")
      expect(raw).to be_a(String)
      # The plaintext access token must NOT be present in the stored blob.
      expect(raw).not_to include("ya29.FAKE")
      # ...but EncryptedTokenCache can recover the original payload.
      decrypted = EncryptedTokenCache.read("gp_access_token:#{credential.id}")
      expect(decrypted[:access_token]).to eq("ya29.FAKE")
    end

    context "when Google's expires_at is sooner than CACHE_TTL" do
      let(:near_expiry_creds) do
        instance_double(
          Google::Auth::ServiceAccountCredentials,
          access_token: "ya29.FAKE",
          expires_at:   Time.now + 2.minutes
        ).tap { |d| allow(d).to receive(:fetch_access_token!).and_return({}) }
      end

      before { allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(near_expiry_creds) }

      it "caches the token for less than the full CACHE_TTL window" do
        expect(Rails.cache).to receive(:write) do |_key, _payload, opts|
          expect(opts[:expires_in].to_i).to be < described_class::CACHE_TTL.to_i
          expect(opts[:expires_in].to_i).to be > 0
        end
        described_class.mint(credential)
      end
    end

    context "when Google's expires_at is already past (or within the safety pad)" do
      let(:expired_creds) do
        instance_double(
          Google::Auth::ServiceAccountCredentials,
          access_token: "ya29.FAKE",
          expires_at:   Time.now - 1.minute
        ).tap { |d| allow(d).to receive(:fetch_access_token!).and_return({}) }
      end

      before { allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(expired_creds) }

      it "does not cache the token" do
        expect(Rails.cache).not_to receive(:write)
        described_class.mint(credential)
      end
    end
  end
end
