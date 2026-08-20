require "rails_helper"

RSpec.describe EncryptedTokenCache do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  describe ".write / .read" do
    it "stores the value encrypted at rest (plaintext absent from the cache blob)" do
      described_class.write("tok:1", { access_token: "super-secret-token", n: 7 })

      raw = store.read("tok:1")
      expect(raw).to be_a(String)
      expect(raw).not_to include("super-secret-token")
    end

    it "round-trips the original value (incl. symbol keys and Time)" do
      ts = Time.now
      described_class.write("tok:2", { access_token: "abc", expires_at: ts, account: 5 })

      out = described_class.read("tok:2")
      expect(out[:access_token]).to eq("abc")
      expect(out[:expires_at]).to be_within(1.second).of(ts)
      expect(out[:account]).to eq(5)
    end

    it "returns nil for a missing key" do
      expect(described_class.read("nope")).to be_nil
    end

    it "honors expires_in (value gone after TTL elapses)" do
      described_class.write("tok:3", "x", expires_in: 1.second)
      expect(described_class.read("tok:3")).to eq("x")
      travel_to(2.seconds.from_now) do
        expect(described_class.read("tok:3")).to be_nil
      end
    end
  end

  describe "decrypt failure" do
    it "treats a corrupt/unencrypted blob as a cache miss (returns nil)" do
      store.write("tok:4", "not-an-encrypted-blob")
      expect(described_class.read("tok:4")).to be_nil
    end

    it "treats a blob encrypted under a different key as a miss" do
      other = ActiveSupport::MessageEncryptor.new(SecureRandom.random_bytes(32), cipher: "aes-256-gcm")
      store.write("tok:5", other.encrypt_and_sign("secret"))
      expect(described_class.read("tok:5")).to be_nil
    end
  end

  describe ".fetch" do
    it "runs the block on a miss, caches, and re-uses on the next call" do
      calls = 0
      v1 = described_class.fetch("tok:6") { calls += 1; "minted" }
      v2 = described_class.fetch("tok:6") { calls += 1; "minted-again" }

      expect(v1).to eq("minted")
      expect(v2).to eq("minted") # served from cache
      expect(calls).to eq(1)
    end

    it "re-mints when the cached blob fails to decrypt" do
      store.write("tok:7", "garbage")
      result = described_class.fetch("tok:7") { "fresh" }
      expect(result).to eq("fresh")
      # the fresh value should now be readable (i.e. re-stored encrypted)
      expect(described_class.read("tok:7")).to eq("fresh")
    end
  end
end
