require "rails_helper"

RSpec.describe CredentialVault::ByokVerifier do
  # KMS stub follows the same shape as spec/services/credential_vault_spec.rb
  # and credential_vault/backfill_spec.rb. We inject the client explicitly
  # via the :kms_client kwarg so we don't rely on global setter state.
  let(:kms) { instance_double(Aws::KMS::Client) }
  let(:org_owner) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: org_owner) }
  let(:key_arn) { "arn:aws:kms:us-east-1:123456789012:key/abcdef01-2345-6789-abcd-ef0123456789" }

  # A canned successful GenerateDataKey response. Contents don't matter —
  # the verifier discards the result; only the lack of an exception matters.
  let(:gdk_response) do
    instance_double("Aws::KMS::Types::GenerateDataKeyResponse",
      plaintext: "x" * 32, ciphertext_blob: "wrapped", key_id: key_arn)
  end

  def verify
    described_class.verify(organization: organization, key_arn: key_arn, kms_client: kms)
  end

  describe "success path" do
    it "returns ok when positive probe succeeds and negative probe is correctly denied" do
      # The verifier hits KMS twice: once with the real org_id (positive,
      # must succeed), once with the all-zeros org_id (negative, must be
      # denied by the customer's key policy condition). Both observations
      # together prove sovereignty AND that the policy condition is in place.
      allow(kms).to receive(:generate_data_key) do |args|
        if args[:encryption_context]["org_id"] == organization.id.to_s
          gdk_response
        else
          raise Aws::KMS::Errors::AccessDeniedException.new(nil, "policy denies wrong org_id")
        end
      end

      result = verify
      expect(result.ok?).to be true
    end

    it "passes the correct encryption_context shape on both probes" do
      # WHY: the EncryptionContext shape (`org_id`, `credential_kind`,
      # `credential_id`) must match what real encrypt calls use. If this
      # drifts, verification would pass against a policy that real encrypts
      # later trip over.
      allow(kms).to receive(:generate_data_key) do |args|
        if args[:encryption_context]["org_id"] == organization.id.to_s
          gdk_response
        else
          raise Aws::KMS::Errors::AccessDeniedException.new(nil, "expected")
        end
      end

      verify

      expect(kms).to have_received(:generate_data_key).with(
        key_id: key_arn,
        key_spec: "AES_256",
        encryption_context: hash_including(
          "org_id" => organization.id.to_s,
          "credential_kind" => "verify",
          "credential_id" => "verify"
        )
      )
      expect(kms).to have_received(:generate_data_key).with(
        key_id: key_arn,
        key_spec: "AES_256",
        encryption_context: hash_including(
          "org_id" => "00000000-0000-0000-0000-000000000000",
          "credential_kind" => "verify",
          "credential_id" => "verify"
        )
      )
    end
  end

  describe "positive-probe failure mapping (mysigner-21)" do
    it "maps NotFoundException to the 'wrong ARN/region' UI message" do
      allow(kms).to receive(:generate_data_key)
        .and_raise(Aws::KMS::Errors::NotFoundException.new(nil, "no such key"))

      result = verify
      expect(result.ok?).to be false
      expect(result.message).to match(/couldn't find that CMK in us-east-1/i)
      expect(result.error_class).to eq("Aws::KMS::Errors::NotFoundException")
    end

    it "maps AccessDeniedException to the 'key policy missing' UI message" do
      allow(kms).to receive(:generate_data_key)
        .and_raise(Aws::KMS::Errors::AccessDeniedException.new(nil, "not authorized"))

      result = verify
      expect(result.ok?).to be false
      expect(result.message).to match(/doesn't grant access to MySigner/)
      expect(result.error_class).to eq("Aws::KMS::Errors::AccessDeniedException")
    end

    it "maps DisabledException to the 'key disabled/pending' UI message" do
      allow(kms).to receive(:generate_data_key)
        .and_raise(Aws::KMS::Errors::DisabledException.new(nil, "key disabled"))

      result = verify
      expect(result.ok?).to be false
      expect(result.message).to match(/disabled or pending deletion/i)
      expect(result.error_class).to eq("Aws::KMS::Errors::DisabledException")
    end

    it "maps KMSInvalidStateException the same way as DisabledException" do
      allow(kms).to receive(:generate_data_key)
        .and_raise(Aws::KMS::Errors::KMSInvalidStateException.new(nil, "pending"))

      result = verify
      expect(result.ok?).to be false
      expect(result.message).to match(/disabled or pending deletion/i)
    end

    it "surfaces other ServiceError messages verbatim" do
      allow(kms).to receive(:generate_data_key)
        .and_raise(Aws::KMS::Errors::ServiceError.new(nil, "kms-quota-exceeded"))

      result = verify
      expect(result.ok?).to be false
      expect(result.message).to eq("kms-quota-exceeded")
    end
  end

  describe "negative-probe failure (missing EncryptionContext condition)" do
    # If the positive probe passes but the NEGATIVE probe ALSO passes, the
    # customer's policy isn't conditioned on `kms:EncryptionContext:org_id`.
    # That's the over-grant case (mysigner-21) — we MUST refuse the
    # registration even though the positive probe was fine.
    it "returns a failure result describing the missing condition" do
      allow(kms).to receive(:generate_data_key).and_return(gdk_response) # both probes succeed

      result = verify
      expect(result.ok?).to be false
      expect(result.message).to match(/missing the required `org_id` condition/)
      expect(result.error_class).to eq("MissingEncryptionContextCondition")
    end
  end
end
