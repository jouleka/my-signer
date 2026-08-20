# Global stub for CredentialVault in the test environment.
#
# Background: post-mysigner-32, the Vaulted concern reads credential plaintext
# exclusively through KMS-wrapped envelope columns. The legacy Rails AR
# Encryption columns are no longer touched. As a consequence, ANY test that
# creates a credential and then reloads it (which is most credential-using
# tests, including BYOK / vault / sso / sync / signing flows) needs CredentialVault
# to be functional — otherwise the reloaded record's accessor returns nil and
# downstream assertions blow up in confusing ways far from the actual root cause.
#
# In production CredentialVault is always wired to real AWS KMS; the
# config/initializers/credential_vault.rb boot check enforces this. In tests we
# install a process-wide stub of `Aws::KMS::Client` that:
#
#   1. Returns a deterministic DEK on `generate_data_key` (so repeated calls
#      produce envelopes with the same DEK, matching the production behavior
#      where the DEK is the only crypto-random part of the envelope per call;
#      tests that need uniqueness can override the stub locally).
#   2. Echoes the same DEK back on `decrypt`, mirroring the real AWS API shape.
#   3. Echoes whichever `key_id` the caller passed (mirrors how real KMS
#      reports the canonical ARN that wrapped the DEK — important for BYOK
#      tests that assert on `envelope.key_id`).
#
# Specs that need to exercise different KMS behavior (failure paths, revocation,
# explicit "KMS not configured" paths, etc.) override the stub locally inside
# their own `before` block. The global stub here is the floor, not the ceiling.
RSpec.configure do |config|
  config.before(:each) do
    # Deterministic per-process DEK so that multiple credential writes within
    # one example produce mathematically-decryptable envelopes. The unwrapping
    # cache in CredentialVault keys on the wrapped_dek hash, so a constant DEK
    # plus a constant wrapped_dek mean every decrypt round-trips cleanly.
    #
    # Using `||=` so a per-example `before` block that has already set the stub
    # (e.g. with custom DEKs for a specific scenario) is not stomped on.
    CredentialVault.instance_variable_set(:@kms_client, nil) if CredentialVault.instance_variable_defined?(:@kms_client)

    test_dek         = "\x00" * 32
    test_wrapped_dek = "test-wrapped-dek".b
    test_key_arn     = "arn:aws:kms:us-east-1:000000000000:key/test-default"

    kms = instance_double(Aws::KMS::Client)
    # generate_data_key echoes whichever CMK ARN the caller asked for. This
    # matches real AWS: the response's key_id is the canonical ARN of the CMK
    # that wrapped the DEK. BYOK tests rely on this to assert that the
    # envelope's key_id reflects the customer's CMK, not the env-default.
    allow(kms).to receive(:generate_data_key) do |args|
      double("GenerateDataKeyResponse",
        plaintext:       test_dek,
        ciphertext_blob: test_wrapped_dek,
        key_id:          (args[:key_id] || test_key_arn)
      )
    end
    allow(kms).to receive(:decrypt) do |args|
      double("DecryptResponse",
        plaintext: test_dek,
        key_id:    args[:key_id]
      )
    end
    allow(kms).to receive(:describe_key) do
      double("DescribeKeyResponse",
        key_metadata: double("KeyMetadata", key_state: "Enabled")
      )
    end

    CredentialVault.kms_client = kms
    CredentialVault.key_arn    = test_key_arn
  end

  config.after(:each) do
    CredentialVault.kms_client = nil
    CredentialVault.key_arn    = nil
  end
end
