require "rails_helper"

# Request-level coverage for the controller-side response to a BYOK CMK
# revocation, plus the rate-limited audit emission. Covers ApplicationController's
# `rescue_from CredentialVault::CustomerKeyRevoked` and the
# `emit_revocation_audit_once` helper (mysigner-21 sub-ticket 2.4).
#
# The unit-level mapping of AWS error classes -> CustomerKeyRevoked is
# covered in spec/services/credential_vault_spec.rb. Here we exercise the
# end-to-end request: an in-flight credential read that hits a revoked CMK
# must produce the user-actionable message + a rate-limited audit row.
#
# Endpoint choice: the Android keystore download path is a clean trigger
# point because it calls `@keystore.keystore_file` (a credential accessor)
# from a Pundit-authorized web controller, so the same single setup
# exercises BOTH the HTML redirect-with-flash branch and the JSON 403 branch.
# We stub the accessor to raise CustomerKeyRevoked — the rescue wiring in
# ApplicationController is what we're testing, not the read path itself.
RSpec.describe "BYOK revocation handling (mysigner-21)", type: :request do
  # MemoryStore swap mirrors spec/requests/auth_failure_audit_spec.rb. Test
  # env's NullStore would no-op the dedup, defeating the whole rate-limit
  # property under test. The stub is per-example, so other specs aren't
  # affected.
  before do
    @memory_store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(@memory_store)

    # AndroidKeystore runs a real keytool-backed validator in before_save
    # (Android::KeystoreValidator#validate!). Calling out to keytool from a
    # spec would either fail (keytool absent) or slow tests down massively;
    # follow the existing pattern from spec/models/android_keystore_spec.rb
    # and stub the validator with a canned result. This isn't what we're
    # testing — we just need a persistable keystore as a vehicle for the
    # revocation rescue.
    validator_result = instance_double(Android::KeystoreValidator::Result,
      valid_until: 1.year.from_now,
      alias: "release",
      certificate_subject: "CN=Demo",
      certificate_issuer: "CN=Demo",
      valid_from: Time.current,
      fingerprints: { sha256: SecureRandom.hex(32) })
    validator = instance_double(Android::KeystoreValidator, validate!: validator_result)
    allow(Android::KeystoreValidator).to receive(:new).and_return(validator)
  end

  let(:owner) do
    User.create!(
      email: "byok-revoke-owner@example.com",
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :team
    )
  end
  let(:organization) { Organization.create!(name: "Revoke Org", owner: owner) }
  let(:byok_arn) do
    "arn:aws:kms:us-east-1:999999999999:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  end
  let(:keystore) { create(:android_keystore, organization: organization) }

  # The error we want the controller's rescue_from to catch. Built without
  # a `cause` so the spec exercises the fallback path in
  # emit_revocation_audit_once (error.cause&.class&.name || error.class.name).
  # The unit spec covers the cause-bearing shape — keeping them split makes
  # the metadata assertions below predictable.
  let(:revocation_error) do
    CredentialVault::CustomerKeyRevoked.new("customer CMK access denied: principal not authorized")
  end

  before do
    sign_in owner
    # Order matters here. Three concerns:
    #
    # 1. The AndroidKeystore factory writes `keystore_file`, and the model's
    #    Vaulted before_save reads it back via the public accessor — so the
    #    accessor stub MUST be installed AFTER the row is materialized.
    #
    # 2. The Vaulted before_save also reads `organization.byok_kms_key_arn`
    #    to decide which CMK to wrap the DEK under. If we set a BYOK ARN
    #    *before* creating the keystore, Vaulted would try to encrypt under
    #    a fake CMK and the create would explode. So: materialize the
    #    keystore against the env-default CMK first, THEN simulate a
    #    customer who registered BYOK afterward (which is also the realistic
    #    timeline anyway — credentials exist, then BYOK gets enabled).
    #
    # 3. The audit metadata reads byok_kms_key_arn from the org at rescue
    #    time, so the ARN must be set on the in-memory record before the
    #    request flows through ApplicationController.
    keystore
    organization.update_column(:byok_kms_key_arn, byok_arn)
    # NOW stub the accessor to raise — simulates "the customer revoked us;
    # the next read can't decrypt".
    allow_any_instance_of(AndroidKeystore).to receive(:keystore_file).and_raise(revocation_error)
  end

  def download_html
    get download_organization_android_keystore_path(organization, keystore)
  end

  def download_json
    get download_organization_android_keystore_path(organization, keystore),
        headers: { "Accept" => "application/json" }
  end

  describe "HTML response" do
    it "responds with a redirect carrying the user-visible message in flash[:alert]" do
      # WHY: the design doc locks the user-facing copy ("Your CMK is
      # unreachable. ...") because sub-ticket 2.5's onboarding doc will quote
      # it verbatim. If a future refactor paraphrases the string, this test
      # fails and forces the doc to be updated in lockstep.
      download_html

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/CMK is unreachable/)
      expect(flash[:alert]).to match(/Settings\s*→\s*Security/)
    end
  end

  describe "JSON response" do
    it "returns 403 with the locked error message and the machine-readable code" do
      # WHY: the `code` field is what a client (CLI, dashboard JS) keys off
      # to decide how to surface this to the user. Generic "forbidden" would
      # conflate with Pundit denials and they'd display the wrong remediation
      # prompt. Pinning the literal "byok_key_revoked" code locks the API
      # contract for downstream consumers.
      download_json

      expect(response).to have_http_status(:forbidden)
      body = response.parsed_body
      expect(body["error"]).to match(/CMK is unreachable/)
      expect(body["code"]).to eq("byok_key_revoked")
    end
  end

  describe "audit emission (rate-limited to 1 per org per 5 minutes)" do
    it "writes exactly one byok_kms_key_revoked_detected audit event on first revocation hit" do
      # WHY: the audit row is the on-call's first signal that a customer's
      # CMK went away. It must contain enough forensic detail (the ARN that
      # used to work, the AWS error class) to begin triage WITHOUT having
      # to ask the customer what they did. If any of those fields drift,
      # the audit becomes useless for the only purpose it has.
      expect { download_html }
        .to change { AuditEvent.where(action: "byok_kms_key_revoked_detected").count }.by(1)

      audit = AuditEvent.where(action: "byok_kms_key_revoked_detected").last
      expect(audit.organization_id).to eq(organization.id)
      expect(audit.metadata["arn"]).to eq(byok_arn)
      # No cause set on this stubbed error -> falls back to the wrapper class.
      # That's the documented behavior in emit_revocation_audit_once.
      expect(audit.metadata["error_class"]).to eq("CredentialVault::CustomerKeyRevoked")
      expect(audit.metadata["error_message"]).to match(/access denied/)
    end

    it "does NOT emit a second audit event when a second revocation hits within 5 minutes" do
      # WHY: a customer who revokes their CMK while the app is under load
      # could trigger thousands of revocation rescues per minute. One audit
      # per 5-minute window per org is sufficient for incident detection;
      # the dashboard would otherwise become unusable during the outage.
      # If this regresses, the audit table gets DoS'd from the inside.
      download_html
      initial_count = AuditEvent.where(action: "byok_kms_key_revoked_detected").count
      expect(initial_count).to eq(1)

      # Pin the cache mechanism itself, not just the outcome. A bare
      # `not_to change { count }` would also pass if the FIRST emission
      # silently failed (0 → 0). Asserting the dedup key actually got
      # written ties the spec to the rate-limit implementation, not just
      # to the absence of new audit rows.
      expect(@memory_store.exist?("byok_revoke_warned:#{organization.id}")).to be true

      expect { download_html }
        .not_to change { AuditEvent.where(action: "byok_kms_key_revoked_detected").count }
    end

    it "emits a fresh audit event after the 5-minute rate-limit window expires" do
      # WHY: the dedup must use a real TTL, not "ever-recorded". Otherwise
      # a transient revocation (customer fixes their policy within 10 minutes)
      # followed by a second revocation a day later would never produce a
      # second audit row, and the on-call would miss the recurrence.
      # `travel_to` exercises the real MemoryStore TTL semantics — a typo
      # of `5.minutes` -> `5.hours` would silently pass without this test.
      download_html
      expect(AuditEvent.where(action: "byok_kms_key_revoked_detected").count).to eq(1)

      travel_to(6.minutes.from_now) do
        expect { download_html }
          .to change { AuditEvent.where(action: "byok_kms_key_revoked_detected").count }.by(1)
      end
    end
  end
end
