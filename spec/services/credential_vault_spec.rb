require "rails_helper"

RSpec.describe CredentialVault do
  let(:kms)                 { instance_double(Aws::KMS::Client) }
  let(:key_arn)             { "arn:aws:kms:us-east-1:123456789012:key/test-key-id" }
  let(:returned_kms_key_id) { "arn:aws:kms:us-east-1:123456789012:key/test-key-id" }
  let(:plaintext)           { "Apple-Authentication-Key-PEM-content".b }
  let(:context)             { { org_id: "org-1", credential_kind: "asc", credential_id: "cred-42" } }
  let(:plaintext_dek)       { OpenSSL::Random.random_bytes(32) }
  let(:wrapped_dek)         { "wrapped-#{SecureRandom.hex(16)}".b }

  before do
    described_class.kms_client = kms
    described_class.key_arn    = key_arn
    Rails.cache.clear
    # H-1/M-2: DEKs now live in a process-local cache, not Rails.cache. Clear
    # the singleton between examples so cached plaintext DEKs don't leak across
    # tests (and so KMS-call-count assertions are deterministic).
    CredentialVault::DekCache.instance.clear
  end

  after do
    described_class.kms_client = nil
    described_class.key_arn    = nil
    CredentialVault::DekCache.instance.clear
  end

  def stub_generate_data_key
    allow(kms).to receive(:generate_data_key).and_return(
      double("GenerateDataKeyResponse",
        plaintext:       plaintext_dek,
        ciphertext_blob: wrapped_dek,
        key_id:          returned_kms_key_id
      )
    )
  end

  def stub_decrypt_success
    allow(kms).to receive(:decrypt).and_return(
      double("DecryptResponse", plaintext: plaintext_dek, key_id: returned_kms_key_id)
    )
  end

  describe ".encrypt" do
    before { stub_generate_data_key }

    it "returns a populated Envelope with AES-GCM-shaped fields" do
      envelope = described_class.encrypt(plaintext, context: context)

      expect(envelope).to have_attributes(
        wrapped_dek: wrapped_dek,
        key_id:      returned_kms_key_id,
        alg_version: CredentialVault::CURRENT_ALG
      )
      # IV is the AES-GCM standard 12-byte nonce; auth_tag is the 16-byte
      # GCM authentication tag. Asserting on bytesize guards against an
      # accidental cipher swap (e.g. AES-CBC, which has different shapes).
      expect(envelope.iv.bytesize).to       eq(12)
      expect(envelope.auth_tag.bytesize).to eq(16)
      expect(envelope.ciphertext.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it "passes context to KMS GenerateDataKey as EncryptionContext (stringified)" do
      # WHY: KMS binds the wrapped DEK to the EncryptionContext at the AWS
      # boundary. If we don't pass it here, an attacker who steals a wrapped
      # DEK can ask KMS to unwrap it without any record-level scoping.
      described_class.encrypt(plaintext, context: context)

      expect(kms).to have_received(:generate_data_key).with(
        key_id:   key_arn,
        key_spec: "AES_256",
        encryption_context: {
          "org_id"          => "org-1",
          "credential_kind" => "asc",
          "credential_id"   => "cred-42"
        }
      )
    end

    it "raises ArgumentError when context is missing required keys" do
      expect { described_class.encrypt(plaintext, context: { org_id: "x" }) }
        .to raise_error(ArgumentError, /credential_kind/)
    end

    it "raises ArgumentError when context has blank values" do
      bad = { org_id: "x", credential_kind: "asc", credential_id: "" }
      expect { described_class.encrypt(plaintext, context: bad) }
        .to raise_error(ArgumentError, /blank values for: credential_id/)
    end

    it "encrypts binary payloads (the .jks case) without crashing" do
      binary = "\x00\x01\xfe\xff".b
      envelope = described_class.encrypt(binary, context: context)

      # Sanity: the ciphertext genuinely transforms the input. If GCM was
      # accidentally configured as a passthrough, this assertion would fail
      # and we'd catch it instead of silently storing plaintext.
      expect(envelope.ciphertext).not_to eq(binary)
    end

    context "with an explicit BYOK key_arn override (mysigner-21 sub-ticket 2.3)" do
      # WHY: BYOK threads the customer's CMK ARN into encrypt via this kwarg.
      # The envelope's `key_id` MUST reflect whichever CMK KMS actually used,
      # because decrypt routes back via `envelope.key_id` — if the override
      # were silently dropped, the wrapped DEK and the routing key would
      # mismatch and decrypt would fail later in a much more obscure place.
      let(:customer_arn) do
        "arn:aws:kms:us-east-1:999999999999:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      end

      it "passes the explicit key_arn to KMS GenerateDataKey as key_id" do
        described_class.encrypt(plaintext, context: context, key_arn: customer_arn)

        expect(kms).to have_received(:generate_data_key).with(
          key_id:   customer_arn,
          key_spec: "AES_256",
          encryption_context: hash_including("org_id" => "org-1")
        )
      end

      it "produces an envelope whose key_id is the CMK that KMS actually wrapped under" do
        # Stub KMS to echo the customer ARN back as the key_id (mirrors the
        # real AWS response shape: generate_data_key returns the full ARN of
        # the CMK that wrapped the DEK).
        allow(kms).to receive(:generate_data_key).and_return(
          double("GenerateDataKeyResponse",
            plaintext:       plaintext_dek,
            ciphertext_blob: wrapped_dek,
            key_id:          customer_arn
          )
        )

        envelope = described_class.encrypt(plaintext, context: context, key_arn: customer_arn)

        # This is the critical assertion: the envelope's key_id is what
        # decrypt will route by. If the BYOK override didn't actually take
        # effect, the env-default CMK's ARN would end up here instead and
        # the test would catch it.
        expect(envelope.key_id).to eq(customer_arn)
      end

      it "falls back to the env-default CMK when key_arn: is nil (Epic 1 behavior preserved)" do
        # WHY: existing Epic 1 callers don't pass `key_arn:`. The kwarg
        # default of nil must mean "use the env default" — otherwise the
        # additive-only-change promise (CredentialVault.encrypt signature)
        # is broken and every existing call site silently encrypts under
        # whatever nil resolves to at the AWS SDK boundary.
        described_class.encrypt(plaintext, context: context, key_arn: nil)

        expect(kms).to have_received(:generate_data_key).with(
          hash_including(key_id: key_arn)
        )
      end

      it "falls back to the env-default CMK when key_arn: is omitted entirely" do
        # Same property as above but exercising the kwarg's default value
        # explicitly. Catches a future refactor that flips the default to
        # something other than nil (which would silently change semantics).
        described_class.encrypt(plaintext, context: context)

        expect(kms).to have_received(:generate_data_key).with(
          hash_including(key_id: key_arn)
        )
      end
    end
  end

  describe ".decrypt" do
    # Build a real encrypted envelope (real AES) with stubbed KMS, then
    # exercise the decrypt path against it. This keeps all the OpenSSL work
    # real so we catch real cipher bugs, not just mock-arrangement bugs.
    let(:envelope) do
      stub_generate_data_key
      described_class.encrypt(plaintext, context: context)
    end

    context "with matching context" do
      before { stub_decrypt_success }

      it "roundtrips to the original plaintext" do
        # WHY: this is the most basic correctness contract of the vault.
        # If this ever fails, every encrypted credential in the DB becomes
        # unreadable. It's the smoke test that gates everything else.
        expect(described_class.decrypt(envelope, context: context)).to eq(plaintext)
      end

      it "passes the same EncryptionContext to KMS Decrypt" do
        described_class.decrypt(envelope, context: context)

        expect(kms).to have_received(:decrypt).with(
          ciphertext_blob:    envelope.wrapped_dek,
          key_id:             envelope.key_id,
          encryption_context: {
            "org_id"          => "org-1",
            "credential_kind" => "asc",
            "credential_id"   => "cred-42"
          }
        )
      end

      it "caches the unwrapped DEK so repeated decrypts hit KMS once" do
        # WHY: KMS calls cost money AND latency. The cache makes
        # signing-time decrypts O(1) KMS calls per credential per hour.
        # If this regresses, every ASC sign becomes a KMS round-trip.
        # Post H-1/M-2 the cache is the process-local DekCache, which is real
        # in test (unlike the old NullStore Rails.cache), so we can now assert
        # the KMS call count directly.
        described_class.decrypt(envelope, context: context)
        described_class.decrypt(envelope, context: context)

        expect(kms).to have_received(:decrypt).once
      end
    end

    context "context binding — the swap-attack defense" do
      # The MOST IMPORTANT security property: an attacker with read access
      # to the DB cannot move a wrapped DEK from row A onto row B and have
      # it decrypt. KMS catches it first; AES-GCM catches it second.

      it "raises DecryptError when KMS rejects the wrapped DEK" do
        # Simulates: KMS sees wrong EncryptionContext and refuses.
        allow(kms).to receive(:decrypt).and_raise(
          Aws::KMS::Errors::InvalidCiphertextException.new(nil, "context mismatch")
        )

        expect { described_class.decrypt(envelope, context: context) }
          .to raise_error(CredentialVault::DecryptError, /KMS rejected wrapped DEK/)
      end

      it "raises DecryptError when AES-GCM auth_tag check fails" do
        # Simulates: even if KMS somehow unwrapped the DEK (test-only
        # scenario), AES-GCM auth_data binding fails the integrity check.
        # This proves the second layer is in place — defense in depth.
        stub_decrypt_success
        wrong_context = context.merge(credential_id: "different-cred-id")

        expect { described_class.decrypt(envelope, context: wrong_context) }
          .to raise_error(CredentialVault::DecryptError, /integrity check failed/)
      end
    end

    context "BYOK revocation handling (mysigner-21 sub-ticket 2.4)" do
      # WHY: When a customer revokes our access to their CMK (removes our
      # principal from the key policy, disables the key, or schedules its
      # deletion), KMS reports the failure with a *different* exception class
      # than the swap-attack / tampering case. Mapping those onto a distinct
      # subclass lets the controller layer distinguish "we can't talk to
      # the customer's CMK anymore — they need to act" from "this envelope
      # is bad" (which would warrant on-call attention, not a customer-
      # actionable 403). Conflating them would either spam operators with
      # false alarms or leave revoked customers staring at a generic 500.
      #
      # Critically: the same AWS error classes (AccessDenied, KMSInvalidState)
      # can ALSO fire when our own env-default CMK is what's unreachable
      # (our IAM principal got disabled, our CMK got disabled). Those are
      # MySigner-internal incidents, NOT BYOK revocations. The decrypt path
      # gates CustomerKeyRevoked on whether the envelope was wrapped under
      # a non-env-default CMK — see customer_managed_envelope? in
      # credential_vault.rb. The pair of tests below pins both halves of
      # that classification, because misclassifying the internal-incident
      # case would emit `byok_kms_key_revoked_detected` audit rows against
      # orgs whose CMKs had nothing to do with the failure.

      let(:customer_arn) { "arn:aws:kms:us-east-1:999999999999:key/customer-cmk-id" }
      let(:byok_envelope) do
        # Encrypt with an explicit key_arn override so the resulting
        # envelope's key_id reflects the customer's CMK, not the env
        # default. This is the prerequisite for customer_managed_envelope?
        # to return true and the rescue chain to raise CustomerKeyRevoked.
        allow(kms).to receive(:generate_data_key).and_return(
          double("GenerateDataKeyResponse",
            plaintext:       plaintext_dek,
            ciphertext_blob: wrapped_dek,
            key_id:          customer_arn
          )
        )
        described_class.encrypt(plaintext, context: context, key_arn: customer_arn)
      end

      it "raises CustomerKeyRevoked when AccessDeniedException hits a customer-CMK envelope" do
        # Simulates: customer pulled our principal out of THEIR CMK's policy.
        # envelope.key_id != env-default → customer_managed_envelope? → true.
        allow(kms).to receive(:decrypt).and_raise(
          Aws::KMS::Errors::AccessDeniedException.new(nil, "principal not authorized")
        )

        expect { described_class.decrypt(byok_envelope, context: context) }
          .to raise_error(CredentialVault::CustomerKeyRevoked, /access denied/)
      end

      it "raises CustomerKeyRevoked when KMSInvalidStateException hits a customer-CMK envelope" do
        # Simulates: customer disabled THEIR CMK or scheduled it for deletion.
        allow(kms).to receive(:decrypt).and_raise(
          Aws::KMS::Errors::KMSInvalidStateException.new(nil, "key is disabled")
        )

        expect { described_class.decrypt(byok_envelope, context: context) }
          .to raise_error(CredentialVault::CustomerKeyRevoked, /disabled or pending deletion/)
      end

      it "raises plain DecryptError (NOT CustomerKeyRevoked) on AccessDenied for env-default envelope" do
        # WHY: this is the misclassification guard. The default `envelope`
        # was wrapped under the env-default CMK (key_arn). If our own IAM
        # principal loses access to our CMK, KMS returns AccessDeniedException
        # — but this is an internal MySigner incident, not BYOK revocation.
        # Surfacing it as CustomerKeyRevoked would (a) trigger a 403 telling
        # the customer to fix their key policy when their key isn't even
        # involved, and (b) emit `byok_kms_key_revoked_detected` against
        # a random org's BYOK ARN, polluting forensics. The decrypt path
        # MUST raise plain DecryptError here so the controller treats it
        # as an internal 500 (on-call wakes up, customer sees generic error).
        allow(kms).to receive(:decrypt).and_raise(
          Aws::KMS::Errors::AccessDeniedException.new(nil, "principal not authorized")
        )

        # Match the exact class (not subclass) so CustomerKeyRevoked can't
        # silently pass this check via its inheritance from DecryptError —
        # the InvalidCiphertextException test below uses the same idiom.
        begin
          described_class.decrypt(envelope, context: context)
          raise "expected DecryptError but none was raised"
        rescue => e
          expect(e.class).to eq(CredentialVault::DecryptError)
          expect(e.message).to match(/internal MySigner incident/)
        end
      end

      it "raises plain DecryptError (NOT CustomerKeyRevoked) on KMSInvalidState for env-default envelope" do
        # Symmetric to the AccessDenied internal-incident case. Our own CMK
        # being Disabled/PendingDeletion is an internal incident; it must
        # not produce a BYOK-shaped 403.
        allow(kms).to receive(:decrypt).and_raise(
          Aws::KMS::Errors::KMSInvalidStateException.new(nil, "key is disabled")
        )

        expect { described_class.decrypt(envelope, context: context) }
          .to raise_error(CredentialVault::DecryptError, /internal incident/)
      end

      it "CustomerKeyRevoked is a subclass of DecryptError (existing rescue patterns still catch it)" do
        # WHY: this is an ADDITIVE-ONLY change. Any existing code with
        # `rescue CredentialVault::DecryptError` must continue to catch a
        # revocation failure too — silently swallowing it would be fine
        # (caller can't do anything about it), but a new failure mode that
        # bypasses existing rescues would be a regression. Asserting the
        # inheritance relationship pins the contract.
        expect(CredentialVault::CustomerKeyRevoked.ancestors).to include(CredentialVault::DecryptError)

        allow(kms).to receive(:decrypt).and_raise(
          Aws::KMS::Errors::AccessDeniedException.new(nil, "denied")
        )
        expect { described_class.decrypt(byok_envelope, context: context) }
          .to raise_error(CredentialVault::DecryptError) # superclass match
      end

      it "leaves the InvalidCiphertextException branch untouched (regression check)" do
        # WHY: the BYOK revocation rescues sit BEFORE InvalidCiphertextException
        # in the rescue chain. If a future refactor reordered them or made one
        # broader than intended, the swap-attack defense would silently get
        # remapped onto CustomerKeyRevoked — and operators would think
        # revocation is happening when really a tamper attempt is. Pin the
        # original behavior here so that reorder fails loudly.
        allow(kms).to receive(:decrypt).and_raise(
          Aws::KMS::Errors::InvalidCiphertextException.new(nil, "context mismatch")
        )

        # Assert exact class (not subclass): the swap-attack path must remain
        # a plain DecryptError, never get auto-promoted into CustomerKeyRevoked.
        begin
          described_class.decrypt(envelope, context: context)
          raise "expected an exception but none was raised"
        rescue => e
          expect(e.class).to eq(CredentialVault::DecryptError)
          expect(e.message).to match(/KMS rejected wrapped DEK/)
        end
      end
    end

    context "tampered envelope" do
      before { stub_decrypt_success }

      it "raises DecryptError when ciphertext is mutated" do
        tampered = envelope.dup
        tampered.ciphertext = "tampered" + envelope.ciphertext[8..]

        expect { described_class.decrypt(tampered, context: context) }
          .to raise_error(CredentialVault::DecryptError, /integrity check failed/)
      end

      it "raises DecryptError when auth_tag is mutated" do
        tampered = envelope.dup
        tampered.auth_tag = "\x00" * 16

        expect { described_class.decrypt(tampered, context: context) }
          .to raise_error(CredentialVault::DecryptError, /integrity check failed/)
      end
    end

    context "with unsupported alg_version" do
      it "raises CredentialVault::Error" do
        # WHY: if we ever bump CURRENT_ALG and an old envelope sneaks through
        # without a corresponding decrypt branch, we want a loud, specific
        # failure — not a silent OpenSSL crash deep in the stack.
        forward_compat = envelope.dup
        forward_compat.alg_version = 999

        expect { described_class.decrypt(forward_compat, context: context) }
          .to raise_error(CredentialVault::Error, /unsupported alg_version=999/)
      end
    end
  end

  describe ".healthy?" do
    it "is true when KMS describe_key returns key_state == 'Enabled'" do
      allow(kms).to receive(:describe_key).and_return(
        double("DescribeKeyResponse",
          key_metadata: double("KeyMetadata", key_state: "Enabled")
        )
      )

      expect(described_class.healthy?).to be true
    end

    it "is false when describe_key raises a service error" do
      allow(kms).to receive(:describe_key).and_raise(
        Aws::KMS::Errors::AccessDeniedException.new(nil, "no")
      )

      expect(described_class.healthy?).to be false
    end

    it "is false when key_state is anything other than 'Enabled'" do
      # PendingDeletion / Disabled / PendingImport all map to false so that
      # health checks fail loudly during key rotation or accidental disable.
      allow(kms).to receive(:describe_key).and_return(
        double("DescribeKeyResponse",
          key_metadata: double("KeyMetadata", key_state: "Disabled")
        )
      )

      expect(described_class.healthy?).to be false
    end
  end

  describe ".pack / .unpack" do
    before { stub_generate_data_key }

    it "round-trips an Envelope through JSON+base64" do
      original = described_class.encrypt(plaintext, context: context)
      packed   = described_class.pack(original)
      unpacked = described_class.unpack(packed)

      # All six fields must survive the round-trip byte-for-byte. If iv or
      # auth_tag changed (e.g. encoding got mangled), AES-GCM decrypt would
      # silently produce garbage or raise — catch it here at the layer it
      # belongs to.
      expect(unpacked).to have_attributes(
        ciphertext:  original.ciphertext,
        wrapped_dek: original.wrapped_dek,
        iv:          original.iv,
        auth_tag:    original.auth_tag,
        key_id:      original.key_id,
        alg_version: original.alg_version
      )
    end

    it "produces a string of valid JSON" do
      original = described_class.encrypt(plaintext, context: context)
      packed   = described_class.pack(original)

      expect(packed).to be_a(String)
      expect { JSON.parse(packed) }.not_to raise_error
    end

    it "an envelope that round-trips through pack/unpack still decrypts" do
      # End-to-end test: encrypt → pack → unpack → decrypt → plaintext.
      # This is the actual flow used by Vaulted models in production.
      allow(kms).to receive(:decrypt).and_return(
        double("DecryptResponse", plaintext: plaintext_dek, key_id: returned_kms_key_id)
      )
      packed = described_class.pack(described_class.encrypt(plaintext, context: context))

      expect(described_class.decrypt(described_class.unpack(packed), context: context)).to eq(plaintext)
    end

    it "raises KeyError when a required field is missing from the packed JSON" do
      # Catches a corruption scenario — partial envelope JSON should fail
      # loudly with a clear KeyError rather than silently producing nil fields.
      expect { described_class.unpack('{"v":1,"kid":"x"}') }
        .to raise_error(KeyError)
    end
  end

  describe "DEK cache is process-local, NOT Rails.cache (mysigner H-1 / M-2)" do
    # WHY: plaintext DEKs must never be written to Rails.cache — in production
    # that is Solid Cache, an UNENCRYPTED Postgres table. Caching key material
    # there would put it on disk in the clear and defeat envelope encryption.
    # The cache now lives in the process-local CredentialVault::DekCache (RAM
    # only). These specs pin that the plaintext DEK never reaches Rails.cache
    # and that the cache is the in-memory one.

    let(:env_envelope) do
      stub_generate_data_key
      described_class.encrypt(plaintext, context: context)
    end

    before do
      allow(kms).to receive(:decrypt).and_return(
        double("DKR", plaintext: plaintext_dek, key_id: returned_kms_key_id)
      )
    end

    it "does NOT write the plaintext DEK to Rails.cache" do
      spy_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(spy_store)

      described_class.decrypt(env_envelope, context: context)

      # No DEK-shaped key, and crucially the raw plaintext DEK bytes must not
      # appear anywhere in the Rails.cache store.
      data = spy_store.instance_variable_get(:@data)
      expect(data.keys.grep(/credential_vault:dek/)).to be_empty
      serialized = Marshal.dump(data) rescue data.inspect
      expect(serialized).not_to include(plaintext_dek)
    end

    it "stores the DEK in the process-local DekCache instead" do
      described_class.decrypt(env_envelope, context: context)

      cache_key = described_class.send(:dek_cache_key, env_envelope.wrapped_dek, env_envelope.key_id)
      cached = CredentialVault::DekCache.fetch(cache_key, ttl: 60) { "MISS" }
      expect(cached).to eq(plaintext_dek)
    end

    it "still honors MYSIGNER_DEK_CACHE_VERSION in the (in-memory) cache key" do
      key_v1 = described_class.send(:dek_cache_key, env_envelope.wrapped_dek, env_envelope.key_id)
      expect(key_v1).to match(/credential_vault:dek:v1:/)

      orig = ENV["MYSIGNER_DEK_CACHE_VERSION"]
      begin
        ENV["MYSIGNER_DEK_CACHE_VERSION"] = "2"
        key_v2 = described_class.send(:dek_cache_key, env_envelope.wrapped_dek, env_envelope.key_id)
        expect(key_v2).to match(/credential_vault:dek:v2:/)
        expect(key_v2).not_to eq(key_v1)
      ensure
        orig ? ENV["MYSIGNER_DEK_CACHE_VERSION"] = orig : ENV.delete("MYSIGNER_DEK_CACHE_VERSION")
      end
    end
  end

  describe "BYOK DEKs use a short cache TTL (M-2 fail-closed revocation)" do
    let(:customer_arn) { "arn:aws:kms:us-east-1:999999999999:key/customer-cmk" }
    let(:byok_envelope) do
      allow(kms).to receive(:generate_data_key).and_return(
        double("GDK", plaintext: plaintext_dek, ciphertext_blob: wrapped_dek, key_id: customer_arn)
      )
      described_class.encrypt(plaintext, context: context, key_arn: customer_arn)
    end

    it "uses BYOK_TTL when unwrapping a customer-managed-CMK envelope" do
      allow(kms).to receive(:decrypt).and_return(
        double("DKR", plaintext: plaintext_dek, key_id: customer_arn)
      )
      expect(CredentialVault::DekCache).to receive(:fetch)
        .with(anything, ttl: CredentialVault::DekCache::BYOK_TTL)
        .and_call_original

      described_class.decrypt(byok_envelope, context: context)
    end

    it "uses the long DEFAULT_TTL for an env-default-CMK envelope" do
      env_envelope = begin
        stub_generate_data_key
        described_class.encrypt(plaintext, context: context)
      end
      allow(kms).to receive(:decrypt).and_return(
        double("DKR", plaintext: plaintext_dek, key_id: returned_kms_key_id)
      )
      expect(CredentialVault::DekCache).to receive(:fetch)
        .with(anything, ttl: CredentialVault::DekCache::DEFAULT_TTL)
        .and_call_original

      described_class.decrypt(env_envelope, context: context)
    end
  end

  describe ".evict_dek (L-1)" do
    it "drops the cached plaintext DEK so a re-fetch goes back to KMS" do
      stub_generate_data_key
      allow(kms).to receive(:decrypt).and_return(
        double("DKR", plaintext: plaintext_dek, key_id: returned_kms_key_id)
      )
      envelope = described_class.encrypt(plaintext, context: context)

      described_class.decrypt(envelope, context: context)        # populates cache
      described_class.evict_dek(envelope.wrapped_dek, envelope.key_id)
      described_class.decrypt(envelope, context: context)        # cache miss → KMS again

      expect(kms).to have_received(:decrypt).twice
    end
  end

  describe "audit logging at the decrypt boundary (L-19)" do
    let(:env_envelope) do
      stub_generate_data_key
      described_class.encrypt(plaintext, context: context)
    end

    before do
      allow(kms).to receive(:decrypt).and_return(
        double("DKR", plaintext: plaintext_dek, key_id: returned_kms_key_id)
      )
      Current.user = nil
    end

    it "emits a system-actor audit event when there is no current user (job path)" do
      expect(Audit::Logger).to receive(:log).with(
        hash_including(
          action: "credential_decrypted",
          actor: nil,
          system_actor: true
        )
      )

      described_class.decrypt(env_envelope, context: context)
    end

    it "does NOT emit a decrypt audit event when a current user is set (controller path owns it)" do
      Current.user = create(:user)
      expect(Audit::Logger).not_to receive(:log)

      described_class.decrypt(env_envelope, context: context)
    ensure
      Current.user = nil
    end

    it "never lets an audit failure break the decrypt" do
      allow(Audit::Logger).to receive(:log).and_raise(StandardError, "audit infra down")

      expect(described_class.decrypt(env_envelope, context: context)).to eq(plaintext)
    end
  end

  describe ".configured?" do
    it "is true when key_arn is explicitly set" do
      described_class.key_arn = "arn:aws:kms:us-east-1:0:key/x"
      expect(described_class.configured?).to be true
    end

    it "is true when MYSIGNER_KMS_KEY_ARN env var is set (and explicit setter is nil)" do
      described_class.key_arn = nil
      ClimateControl.modify("MYSIGNER_KMS_KEY_ARN" => "arn:aws:kms:us-east-1:0:key/from-env") do
        expect(described_class.configured?).to be true
      end
    rescue NameError
      # ClimateControl gem not present; fall back to manual ENV manipulation
      described_class.key_arn = nil
      orig = ENV["MYSIGNER_KMS_KEY_ARN"]
      ENV["MYSIGNER_KMS_KEY_ARN"] = "arn:aws:kms:us-east-1:0:key/from-env"
      expect(described_class.configured?).to be true
    ensure
      ENV["MYSIGNER_KMS_KEY_ARN"] = orig if defined?(orig)
    end

    it "is false when neither setter nor env var is set" do
      described_class.key_arn = nil
      orig = ENV.delete("MYSIGNER_KMS_KEY_ARN")
      expect(described_class.configured?).to be false
    ensure
      ENV["MYSIGNER_KMS_KEY_ARN"] = orig if orig
    end
  end
end
