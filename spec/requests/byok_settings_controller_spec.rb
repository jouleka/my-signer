require "rails_helper"

RSpec.describe ByokSettingsController, type: :request do
  let(:team_owner) do
    User.create!(email: "byok-owner@example.com", password: "SecurePassword123!",
                  confirmed_at: Time.current, plan_tier: :team)
  end
  let(:organization) { Organization.create!(name: "BYOK Org", owner: team_owner) }
  let(:valid_arn) { "arn:aws:kms:us-east-1:123456789012:key/abcdef01-2345-6789-abcd-ef0123456789" }

  before { sign_in team_owner }

  # We stub the verifier so request specs don't talk to AWS. Every test in
  # this file forces a known verifier outcome; the verifier itself is
  # covered in spec/services/credential_vault/byok_verifier_spec.rb.
  let(:ok_result) { CredentialVault::ByokVerifier::Result.new(ok: true) }
  let(:failed_result) do
    CredentialVault::ByokVerifier::Result.new(
      ok: false,
      message: "Your key policy doesn't grant access to MySigner. See the BYOK setup guide.",
      error_class: "Aws::KMS::Errors::AccessDeniedException",
      error_message: "not authorized"
    )
  end

  describe "POST /organizations/:organization_id/security/byok/verify" do
    it "returns ok:true JSON when the verifier passes (does NOT save the ARN)" do
      allow(CredentialVault::ByokVerifier).to receive(:verify).and_return(ok_result)

      post organization_verify_byok_settings_path(organization), params: { byok_kms_key_arn: valid_arn }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("ok" => true)
      # Critical: verify is a probe, NOT a save. The column must stay nil.
      expect(organization.reload.byok_kms_key_arn).to be_nil
    end

    it "accepts a JSON-body request from the Stimulus controller (the production path)" do
      # WHY: the Stimulus controller posts Content-Type: application/json
      # with a JSON-encoded body, not form params. A future wrap_parameters
      # config change wrapping under :byok_setting would silently break the
      # Verify button — and no form-params spec would catch it. This spec
      # exercises the JSON code path end-to-end so that regression has
      # somewhere to fail.
      allow(CredentialVault::ByokVerifier).to receive(:verify).and_return(ok_result)

      post organization_verify_byok_settings_path(organization),
           params: { byok_kms_key_arn: valid_arn }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("ok" => true)
    end

    it "returns ok:false JSON with the failure message and emits byok_verify_failed audit" do
      allow(CredentialVault::ByokVerifier).to receive(:verify).and_return(failed_result)

      expect {
        post organization_verify_byok_settings_path(organization), params: { byok_kms_key_arn: valid_arn }
      }.to change { AuditEvent.where(action: "byok_verify_failed").count }.by(1)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["ok"]).to be false
      expect(response.parsed_body["error"]).to match(/doesn't grant access/)
      # Verify audit metadata captures the attempt for forensics.
      audit = AuditEvent.where(action: "byok_verify_failed").last
      expect(audit.metadata["arn"]).to eq(valid_arn)
      expect(audit.metadata["error_class"]).to eq("Aws::KMS::Errors::AccessDeniedException")
    end

    it "rejects malformed ARN format without calling the verifier and audits the failure" do
      # WHY: cheap regex rejection prevents wasted KMS calls and gives the
      # customer a faster, clearer error than a network round-trip would.
      expect(CredentialVault::ByokVerifier).not_to receive(:verify)

      expect {
        post organization_verify_byok_settings_path(organization), params: { byok_kms_key_arn: "alias/whatever" }
      }.to change { AuditEvent.where(action: "byok_verify_failed").count }.by(1)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["ok"]).to be false
    end

    it "returns 403 when the user is not admin/owner (developer role)" do
      # WHY: BYOK is admin/owner-gated regardless of plan tier — the wider
      # cryptographic blast radius rules out developers and viewers even
      # though they can manage other credentials. Hit the JSON path so the
      # spec also covers Pundit's NotAuthorized → 403 JSON translation.
      sign_out team_owner
      developer = create(:user, :team_plan)
      organization.memberships.create!(user: developer, role: :developer)
      sign_in developer

      post organization_verify_byok_settings_path(organization), params: { byok_kms_key_arn: valid_arn }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 when the user is not a member of the org" do
      # Same enumeration-oracle guard as SsoConfigurationsController#set_org:
      # a non-member sees the same response as a non-existent org id. If we
      # returned 403 here, the presence-of-org bit would leak across orgs.
      sign_out team_owner
      outsider = create(:user, :team_plan)
      sign_in outsider

      post organization_verify_byok_settings_path(organization), params: { byok_kms_key_arn: valid_arn }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Team-tier gating (mysigner-36 / M-6)" do
    # The entitlement check runs in a before_action BEFORE Pundit and BEFORE
    # any persistence, so non-Team orgs get the paywall page on every route
    # and nothing is saved/probed.
    context "when the owner's org is on the Pro plan" do
      before { team_owner.update!(plan_tier: :pro) }

      it "renders the Team-feature paywall on PATCH and does NOT save the ARN" do
        # The verifier must never be reached on a paywalled request.
        expect(CredentialVault::ByokVerifier).not_to receive(:verify)

        patch organization_update_byok_settings_path(organization),
              params: { byok_kms_key_arn: valid_arn }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Bring Your Own Key")
        expect(response.body).to include("Team feature")
        expect(organization.reload.byok_kms_key_arn).to be_nil
      end

      it "renders the Team-feature paywall on POST verify without probing KMS" do
        expect(CredentialVault::ByokVerifier).not_to receive(:verify)

        post organization_verify_byok_settings_path(organization),
             params: { byok_kms_key_arn: valid_arn }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Upgrade to Team")
      end
    end

    context "when the owner's org is on the Free plan" do
      before { team_owner.update!(plan_tier: :free) }

      it "renders the Team-feature paywall on PATCH and does NOT save the ARN" do
        patch organization_update_byok_settings_path(organization),
              params: { byok_kms_key_arn: valid_arn }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Team feature")
        expect(organization.reload.byok_kms_key_arn).to be_nil
      end
    end

    it "allows the Team-plan owner through the entitlement gate (no paywall)" do
      # Clear path on an already-blank column is a safe no-op that never
      # touches KMS — a clean way to prove the gate let us through.
      patch organization_update_byok_settings_path(organization), params: { byok_kms_key_arn: "" }

      expect(response.body).not_to include("Team feature")
      expect(response).to redirect_to(organization_path(organization))
    end
  end

  describe "BYOK panel rendering on the org show page" do
    # Smoke test: verifies the panel renders for a manage_byok?-eligible user
    # without crashing on missing helpers / route helpers / partials. Catches
    # NoMethodError-style regressions early. Content assertions kept narrow
    # so this doesn't become brittle to UI tweaks.
    it "renders the BYOK panel for a Team-tier admin/owner" do
      get organization_path(organization)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bring Your Own Key")
      expect(response.body).to include(organization_update_byok_settings_path(organization))
      expect(response.body).to include(organization_verify_byok_settings_path(organization))
    end

    it "shows the upgrade teaser (not the manage panel) for a Pro-tier admin/owner" do
      # WHY (mysigner-36 / M-6): BYOK is now gated behind the Team plan.
      # A Pro-tier admin/owner must NOT get the full manage panel — they see
      # an upgrade teaser, and the actual BYOK routes render the Team-feature
      # paywall. The write affordances (Save/Verify endpoints) must be absent
      # so the dashboard never wires up controls the routes would reject.
      team_owner.update!(plan_tier: :pro)
      get organization_path(organization)
      expect(response).to have_http_status(:ok)
      # Heading still present (it's the teaser), but with the upgrade CTA and
      # WITHOUT the manage-form endpoints.
      expect(response.body).to include("Bring Your Own Key")
      expect(response.body).to include("Upgrade to Team")
      expect(response.body).not_to include(organization_update_byok_settings_path(organization))
      expect(response.body).not_to include(organization_verify_byok_settings_path(organization))
    end
  end

  describe "PATCH /organizations/:organization_id/security/byok (save path)" do
    # Stub OrgRewrap so request specs don't talk to KMS via the org's
    # before_save callback. The OrgRewrap class itself is covered in
    # spec/services/credential_vault/org_rewrap_spec.rb.
    let(:rewrap_counts) do
      {
        AppStoreConnectCredential: { processed: 2, succeeded: 2 },
        GooglePlayCredential:      { processed: 1, succeeded: 1 },
        AndroidKeystore:           { processed: 0, succeeded: 0 },
        AppleAdsCredential:        { processed: 0, succeeded: 0 }
      }
    end

    it "saves the ARN, emits byok_registered audit, and redirects on probe success" do
      allow(CredentialVault::ByokVerifier).to receive(:verify).and_return(ok_result)
      allow(CredentialVault::OrgRewrap).to receive(:run).and_return(rewrap_counts)

      expect {
        patch organization_update_byok_settings_path(organization), params: { byok_kms_key_arn: valid_arn }
      }.to change { AuditEvent.where(action: "byok_registered").count }.by(1)

      expect(organization.reload.byok_kms_key_arn).to eq(valid_arn)
      expect(response).to redirect_to(organization_path(organization))

      audit = AuditEvent.where(action: "byok_registered").last
      expect(audit.metadata["arn"]).to eq(valid_arn)
      # rewrap_counts is now populated from Organization#last_rewrap_counts
      # which the before_save callback set inside the update transaction.
      # We expect every credential model class to appear as a subkey so
      # forensics never have to wonder "did this class even get touched?".
      expect(audit.metadata["rewrap_counts"]).to be_a(Hash)
      expect(audit.metadata["rewrap_counts"].keys).to match_array(%w[
        AppStoreConnectCredential
        GooglePlayCredential
        AndroidKeystore
        AppleAdsCredential
      ])
      # Per-class numbers come from the OrgRewrap stub (JSON round-trip
      # through audit_events.metadata stringifies the inner hash keys, so
      # we compare against the string-keyed equivalent).
      expect(audit.metadata["rewrap_counts"]["AppStoreConnectCredential"]).to eq(
        "processed" => 2, "succeeded" => 2
      )
    end

    it "refuses to save and emits byok_verify_failed audit when the probe fails" do
      allow(CredentialVault::ByokVerifier).to receive(:verify).and_return(failed_result)

      registered_before = AuditEvent.where(action: "byok_registered").count

      expect {
        patch organization_update_byok_settings_path(organization), params: { byok_kms_key_arn: valid_arn }
      }.to change { AuditEvent.where(action: "byok_verify_failed").count }.by(1)

      expect(AuditEvent.where(action: "byok_registered").count).to eq(registered_before)
      expect(organization.reload.byok_kms_key_arn).to be_nil
    end
  end

  describe "PATCH /organizations/:organization_id/security/byok (clear path)" do
    before { organization.update_column(:byok_kms_key_arn, valid_arn) }

    let(:clear_counts) do
      {
        AppStoreConnectCredential: { processed: 1, succeeded: 1 },
        GooglePlayCredential:      { processed: 0, succeeded: 0 },
        AndroidKeystore:           { processed: 0, succeeded: 0 },
        AppleAdsCredential:        { processed: 0, succeeded: 0 }
      }
    end

    it "clears the ARN and emits byok_cleared audit with the previous ARN" do
      allow(CredentialVault::OrgRewrap).to receive(:run).and_return(clear_counts)

      expect {
        patch organization_update_byok_settings_path(organization), params: { byok_kms_key_arn: "" }
      }.to change { AuditEvent.where(action: "byok_cleared").count }.by(1)

      expect(organization.reload.byok_kms_key_arn).to be_nil
      audit = AuditEvent.where(action: "byok_cleared").last
      expect(audit.metadata["previous_arn"]).to eq(valid_arn)
      # rewrap_counts is now populated by the org callback during update!.
      # Same per-class assertion as the register path so forensics see the
      # full picture on a Clear too.
      expect(audit.metadata["rewrap_counts"]).to be_a(Hash)
      expect(audit.metadata["rewrap_counts"].keys).to match_array(%w[
        AppStoreConnectCredential
        GooglePlayCredential
        AndroidKeystore
        AppleAdsCredential
      ])
      expect(audit.metadata["rewrap_counts"]["AppStoreConnectCredential"]).to eq(
        "processed" => 1, "succeeded" => 1
      )
    end

    it "is a no-op (no audit) when the column was already blank" do
      organization.update_column(:byok_kms_key_arn, nil)

      expect {
        patch organization_update_byok_settings_path(organization), params: { byok_kms_key_arn: "" }
      }.not_to change { AuditEvent.where(action: "byok_cleared").count }

      expect(response).to redirect_to(organization_path(organization))
    end

    it "lets a DOWNGRADED (non-Team) org clear BYOK — the recovery off-ramp is NOT paywalled" do
      # Regression guard (review must-fix): an org that enabled BYOK on Team
      # then downgraded must keep the Clear off-ramp. Registering a new CMK
      # stays Team-gated, but clearing (role-only :clear_byok?) must succeed on
      # any tier — otherwise credentials stay wrapped under the customer CMK
      # with no UI path back and a later CMK revoke bricks all decryption.
      allow(CredentialVault::OrgRewrap).to receive(:run).and_return(clear_counts)
      team_owner.update!(plan_tier: :free)

      expect {
        patch organization_update_byok_settings_path(organization), params: { byok_kms_key_arn: "" }
      }.to change { AuditEvent.where(action: "byok_cleared").count }.by(1)

      expect(response).to redirect_to(organization_path(organization))
      expect(response.body).not_to include("Team feature")
      expect(organization.reload.byok_kms_key_arn).to be_nil
    end

    it "still paywalls a non-Team org trying to REGISTER a new CMK (only Clear is exempt)" do
      team_owner.update!(plan_tier: :free)
      expect(CredentialVault::ByokVerifier).not_to receive(:verify)

      patch organization_update_byok_settings_path(organization), params: { byok_kms_key_arn: valid_arn }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Team feature")
      # The pre-existing ARN is untouched — register was blocked.
      expect(organization.reload.byok_kms_key_arn).to eq(valid_arn)
    end
  end

  describe "BYOK panel visibility for non-admin members" do
    # WHY: BYOK is admin/owner-scoped. On a Team org the tier gate is
    # satisfied, so this isolates the ROLE gate: developers and viewers must
    # NOT see the BYOK section (neither the manage panel nor the upgrade
    # teaser), even though they're members and can see the org page itself.
    before { organization.update_column(:byok_kms_key_arn, valid_arn) }

    it "hides the BYOK panel from developers regardless of tier" do
      developer = User.create!(email: "byok-dev@example.com", password: "SecurePassword123!",
                               confirmed_at: Time.current, plan_tier: :team)
      organization.memberships.create!(user: developer, role: :developer)

      sign_out team_owner
      sign_in developer

      get organization_path(organization)

      expect(response).to have_http_status(:ok)
      # The developer is a member so they see the org page, but the BYOK
      # section must not appear at all — neither the heading nor the
      # configured ARN should leak to a non-admin.
      expect(response.body).not_to include("Bring Your Own Key")
      expect(response.body).not_to include(valid_arn)
    end
  end
end
