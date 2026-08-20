require "rails_helper"

# Unit specs for the process-local DEK cache (mysigner H-1 / M-2). This cache
# replaces the old Rails.cache DEK store so plaintext key material never leaves
# RAM. These specs exercise the cache directly (no KMS) — the integration with
# CredentialVault.unwrap_dek is covered in credential_vault_spec.rb.
RSpec.describe CredentialVault::DekCache do
  subject(:cache) { described_class.new }

  let(:dek) { OpenSSL::Random.random_bytes(32) }

  describe "#fetch" do
    it "computes and returns the value on a miss" do
      result = cache.fetch("k1", ttl: 60) { dek }
      expect(result).to eq(dek)
    end

    it "returns the cached value without re-invoking the block on a hit" do
      calls = 0
      cache.fetch("k1", ttl: 60) { calls += 1; dek }
      result = cache.fetch("k1", ttl: 60) { calls += 1; "SHOULD-NOT-RUN" }

      expect(result).to eq(dek)
      expect(calls).to eq(1)
    end

    it "treats an expired entry as a miss and re-computes" do
      # Freeze the monotonic clock by stubbing the private reader.
      t = 1000.0
      allow_any_instance_of(described_class).to receive(:monotonic_now) { t }

      cache.fetch("k1", ttl: 30) { "first" }
      t = 1031.0 # 31s later, past the 30s TTL
      result = cache.fetch("k1", ttl: 30) { "second" }

      expect(result).to eq("second")
    end

    it "bypasses caching entirely when ttl is zero (block runs every time)" do
      calls = 0
      cache.fetch("k1", ttl: 0) { calls += 1; "a" }
      cache.fetch("k1", ttl: 0) { calls += 1; "b" }

      expect(calls).to eq(2)
    end
  end

  describe "#delete" do
    it "evicts a cached entry so the next fetch recomputes (L-1)" do
      calls = 0
      cache.fetch("k1", ttl: 600) { calls += 1; "a" }
      cache.delete("k1")
      cache.fetch("k1", ttl: 600) { calls += 1; "b" }

      expect(calls).to eq(2)
    end

    it "is a no-op for a key that was never cached" do
      expect { cache.delete("never") }.not_to raise_error
    end
  end

  describe "#clear" do
    it "drops every entry" do
      calls = 0
      cache.fetch("k1", ttl: 600) { calls += 1; "a" }
      cache.fetch("k2", ttl: 600) { calls += 1; "b" }
      cache.clear
      cache.fetch("k1", ttl: 600) { calls += 1; "a2" }
      cache.fetch("k2", ttl: 600) { calls += 1; "b2" }

      expect(calls).to eq(4)
    end
  end

  describe "TTL constants" do
    it "uses a short TTL for BYOK so CMK revocation fails closed quickly (M-2)" do
      expect(described_class::BYOK_TTL).to be <= 120
      expect(described_class::BYOK_TTL).to be < described_class::DEFAULT_TTL
    end
  end

  describe ".instance singleton delegation" do
    it "delegates class-level fetch/delete to a shared instance" do
      described_class.instance.clear
      v = described_class.fetch("shared", ttl: 600) { "X" }
      expect(v).to eq("X")
      expect(described_class.fetch("shared", ttl: 600) { "Y" }).to eq("X")

      described_class.delete("shared")
      expect(described_class.fetch("shared", ttl: 600) { "Z" }).to eq("Z")
    ensure
      described_class.instance.clear
    end
  end
end
