require "aws-sdk-kms"

# Verifies a customer's BYOK CMK ARN by exercising the same code path real
# encrypt calls will take. Two probes, both `kms:GenerateDataKey`:
#
#   1. POSITIVE — with the customer's real org_id in the encryption context.
#      Expected: succeeds.
#   2. NEGATIVE — with a deliberately wrong org_id (the all-zeros UUID).
#      Expected: fails with AccessDeniedException, because the customer's
#      key policy must condition on `kms:EncryptionContext:org_id`. If this
#      probe SUCCEEDS, the policy over-grants and we refuse the registration.
#
# Why module-level helper and not a CredentialVault method: sub-ticket 2.2
# (this) deliberately keeps CredentialVault.encrypt's public signature
# unchanged. Sub-ticket 2.3 adds the `key_arn:` kwarg. This verifier exists
# alongside CredentialVault, not inside it, so 2.2 can stand alone.
#
# Failure-mapping table this implements is tracked in mysigner-21.
class CredentialVault
  class ByokVerifier
    # All-zeros UUID used as the "wrong org_id" in the negative probe. Picked
    # because no real Organization can ever have this id (Postgres uuid type
    # rejects ad-hoc collisions and our use of gen_random_uuid() makes the
    # all-zero value astronomically unlikely to be a real org id).
    NEGATIVE_PROBE_ORG_ID = "00000000-0000-0000-0000-000000000000"

    # Structured result. `ok` is the only field most callers read; the
    # message + error_class fields are for audit/UI display when ok is false.
    Result = Struct.new(:ok, :message, :error_class, :error_message, keyword_init: true) do
      def ok?
        ok == true
      end
    end

    # @param organization [Organization]
    # @param key_arn [String] the full KMS key ARN to verify
    # @param kms_client [Aws::KMS::Client, nil] optional override for tests.
    #   When nil, builds a fresh client pinned to us-east-1 — NOT
    #   CredentialVault.kms_client, which is for our env CMK. The customer's
    #   CMK is a different resource even though our IAM principal is the
    #   same; using a dedicated client keeps the call sites grep-able.
    def self.verify(organization:, key_arn:, kms_client: nil)
      new(organization: organization, key_arn: key_arn, kms_client: kms_client).verify
    end

    def initialize(organization:, key_arn:, kms_client: nil)
      @organization = organization
      @key_arn = key_arn
      @kms_client = kms_client
    end

    # Runs both probes, returns a Result. The positive probe runs first
    # because its failure modes are the most actionable for the customer
    # (wrong ARN, no permission, key disabled). Only when the positive probe
    # passes do we run the negative probe to check the EncryptionContext
    # condition is present.
    def verify
      positive_result = run_positive_probe
      return positive_result unless positive_result.ok?

      run_negative_probe
    end

    private

    attr_reader :organization, :key_arn

    def kms_client
      @kms_client ||= Aws::KMS::Client.new(region: "us-east-1")
    end

    def run_positive_probe
      kms_client.generate_data_key(
        key_id:             key_arn,
        key_spec:           "AES_256",
        encryption_context: encryption_context(org_id: organization.id.to_s)
      )
      Result.new(ok: true)
    rescue Aws::KMS::Errors::NotFoundException => e
      failure(e, "We couldn't find that CMK in us-east-1. Check the ARN and the region.")
    rescue Aws::KMS::Errors::AccessDeniedException => e
      failure(e, "Your key policy doesn't grant access to MySigner. See the BYOK setup guide.")
    rescue Aws::KMS::Errors::DisabledException, Aws::KMS::Errors::KMSInvalidStateException => e
      failure(e, "Your CMK is disabled or pending deletion. Enable it before registering.")
    rescue Aws::KMS::Errors::ServiceError => e
      failure(e, e.message)
    end

    def run_negative_probe
      kms_client.generate_data_key(
        key_id:             key_arn,
        key_spec:           "AES_256",
        encryption_context: encryption_context(org_id: NEGATIVE_PROBE_ORG_ID)
      )
      # Reaching here means the customer's policy didn't reject the call
      # despite an org_id that isn't theirs — i.e. the `kms:EncryptionContext:org_id`
      # condition is missing. Sovereignty property is broken; refuse.
      Result.new(
        ok: false,
        message: "Your key policy is missing the required `org_id` condition — see step 3 of the setup guide.",
        error_class: "MissingEncryptionContextCondition",
        error_message: "negative probe succeeded (key policy over-grants)"
      )
    rescue Aws::KMS::Errors::AccessDeniedException
      # Expected — the customer's policy correctly rejected our call with
      # the wrong org_id. Sovereignty property is in place.
      Result.new(ok: true)
    rescue Aws::KMS::Errors::ServiceError => e
      # Any other error on the negative probe is treated as a generic
      # failure. We can't distinguish "policy is correct" from "transient
      # KMS error" without the specific AccessDeniedException, and we'd
      # rather refuse than register against an indeterminate policy. Wrap
      # the AWS message with a "Verification could not complete:" prefix
      # so the customer doesn't read e.g. "Rate exceeded" as a verdict on
      # their key policy.
      failure(e, "Verification could not complete: #{e.message}")
    end

    def encryption_context(org_id:)
      {
        "org_id"          => org_id,
        "credential_kind" => "verify",
        "credential_id"   => "verify"
      }
    end

    def failure(error, message)
      Result.new(
        ok: false,
        message: message,
        error_class: error.class.name,
        error_message: error.message
      )
    end
  end
end
