require "test_helper"

class Users::AccountRestorationsTest < ActionDispatch::IntegrationTest
  def make_user(**overrides)
    user = User.new({
      email: "u-#{SecureRandom.hex(6)}@example.test",
      password: "Password123!",
      accepts_terms: "1"
    }.merge(overrides))
    user.skip_confirmation!
    user.save!
    user
  end

  def with_oauth_mock(provider, auth_hash)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[provider.to_sym] = auth_hash
    yield
  ensure
    OmniAuth.config.mock_auth[provider.to_sym] = nil
    OmniAuth.config.test_mode = false
  end

  test "GET /account/restore with a valid (within-window) token renders successfully" do
    user = make_user
    plain_token = user.soft_delete!

    get account_restoration_path, params: { token: plain_token }

    assert_response :success
  end

  test "GET /account/restore with a missing/blank token returns 404 (not found)" do
    get account_restoration_path
    assert_response :not_found

    get account_restoration_path, params: { token: "" }
    assert_response :not_found
  end

  test "GET /account/restore with an unknown token returns 404" do
    get account_restoration_path, params: { token: "totally-fake-token-xxxxxxxxxxxx" }
    assert_response :not_found
  end

  test "GET /account/restore with an expired (>90 days) token returns 410 (gone)" do
    user = make_user
    plain_token = user.soft_delete!
    user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)

    get account_restoration_path, params: { token: plain_token }

    assert_response :gone
  end

  test "POST /account/restore with valid token AND correct password restores account, signs the user in, redirects" do
    user = make_user
    plain_token = user.soft_delete!

    post account_restoration_path, params: { token: plain_token, current_password: "Password123!" }

    user.reload
    refute user.deleted?, "deleted_at must be cleared"
    assert_nil user.deletion_token, "deletion_token must be cleared (single-use)"
    assert_response :redirect
  end

  test "POST /account/restore with valid token but WRONG password does NOT restore (M2: bearer-token-only restore is closed)" do
    user = make_user
    plain_token = user.soft_delete!

    post account_restoration_path, params: { token: plain_token, current_password: "WrongPassword123!" }

    user.reload
    assert user.deleted?, "wrong-password restore attempt must NOT clear deleted_at"
    assert_response :unprocessable_content
  end

  test "POST /account/restore with valid token but BLANK password does NOT restore" do
    user = make_user
    plain_token = user.soft_delete!

    post account_restoration_path, params: { token: plain_token, current_password: "" }

    user.reload
    assert user.deleted?, "blank-password restore attempt must NOT clear deleted_at"
    assert_response :unprocessable_content
  end

  test "POST /account/restore for an OAuth user redirects through the original provider for re-auth" do
    user = make_user
    user.update!(provider: "google_oauth2", uid: "g-#{SecureRandom.hex(4)}")
    plain_token = user.soft_delete!

    post account_restoration_path, params: { token: plain_token }

    user.reload
    assert user.deleted?, "OAuth restore must not finalize without provider round-trip"
    assert_response :redirect
    assert_equal "/users/auth/google_oauth2", URI.parse(response.location).path,
      "OAuth user's restore POST must redirect to the original provider's auth endpoint"
    assert_equal plain_token, session[:account_restoration_token],
      "deletion token must be stashed in session for the OAuth callback to consume"
    assert session[:account_restoration_initiated_at].present?,
      "initiated_at timestamp must be stashed for the staleness gate"
  end

  test "OAuth restore happy path: callback with matching (provider, uid) restores and signs in" do
    uid = "google-#{SecureRandom.hex(4)}"
    user = make_user
    user.update!(provider: "google_oauth2", uid: uid)
    plain_token = user.soft_delete!

    with_oauth_mock(:google_oauth2, OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: user.email, email_verified: true }
    )) do
      # Step 1: POST /account/restore stashes the token in session and
      # redirects to the OAuth provider URL.
      post account_restoration_path, params: { token: plain_token }
      assert_redirected_to "/users/auth/google_oauth2"
      # Step 2: hit the callback directly. OmniAuth test mode populates
      # `request.env["omniauth.auth"]` from `mock_auth[:google_oauth2]`,
      # so this exercises `OmniauthCallbacksController#handle_oauth` end
      # to end. Session from step 1 (the restoration token) is preserved
      # across the integration-test request boundary.
      post "/users/auth/google_oauth2/callback"
    end

    user.reload
    refute user.deleted?, "matching-(provider, uid) callback must restore the account"
    assert_nil user.deletion_token, "deletion_token must be cleared (single-use)"
  end

  test "OAuth restore (provider, uid) mismatch: callback with different uid does NOT restore" do
    real_uid = "real-uid-#{SecureRandom.hex(4)}"
    user = make_user
    user.update!(provider: "google_oauth2", uid: real_uid)
    plain_token = user.soft_delete!

    with_oauth_mock(:google_oauth2, OmniAuth::AuthHash.new(
      # Attacker's IdP account: same provider, different uid.
      provider: "google_oauth2",
      uid: "attacker-uid-#{SecureRandom.hex(4)}",
      info: { email: "attacker@example.com" }
    )) do
      post account_restoration_path, params: { token: plain_token }
      assert_redirected_to "/users/auth/google_oauth2"
      post "/users/auth/google_oauth2/callback"
    end

    user.reload
    assert user.deleted?, "callback with mismatched uid must NOT clear deleted_at"
    assert user.deletion_token.present?, "deletion_token must remain (link still usable)"
  end

  test "OAuth restore stale session: callback after the flow TTL does NOT restore" do
    uid = "google-#{SecureRandom.hex(4)}"
    user = make_user
    user.update!(provider: "google_oauth2", uid: uid)
    plain_token = user.soft_delete!

    with_oauth_mock(:google_oauth2, OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: user.email }
    )) do
      # Begin the flow, then time-travel past the TTL before the callback
      # consumes it. Mirrors a session-cookie thief who steals a cookie
      # whose owner abandoned an in-flight restore an hour ago.
      post account_restoration_path, params: { token: plain_token }
      assert_redirected_to "/users/auth/google_oauth2"

      ttl = Users::OmniauthCallbacksController::ACCOUNT_RESTORATION_FLOW_TTL
      travel_to((ttl + 1.minute).from_now) do
        post "/users/auth/google_oauth2/callback"
      end
    end

    user.reload
    assert user.deleted?, "stale-flow callback must NOT clear deleted_at"
  end

  test "POST /account/restore for a SAML JIT user shows a contact-admin error (no self-service path)" do
    user = make_user
    user.update!(provider: "saml_some-org", uid: "saml-uid-#{SecureRandom.hex(4)}")
    plain_token = user.soft_delete!

    post account_restoration_path, params: { token: plain_token }

    user.reload
    assert user.deleted?, "SAML user must not be restored without admin assistance"
    assert_response :unprocessable_content
    assert_match(/admin/i, flash.now[:alert].to_s.presence || @response.body)
  end

  test "POST /account/restore with an unknown token does NOT restore any user (returns 404)" do
    user = make_user
    user.soft_delete!

    post account_restoration_path, params: { token: "wrong-token-xxxxxxxxxxxxxxxxxxx" }

    user.reload
    assert user.deleted?, "soft-deleted user must remain deleted"
    assert_response :not_found
  end

  test "POST /account/restore with an expired token does NOT restore (returns 410)" do
    user = make_user
    plain_token = user.soft_delete!
    user.update_column(:deleted_at, (PendingDeletionPurgeJob::RETENTION_DAYS + 1).days.ago)

    post account_restoration_path, params: { token: plain_token, current_password: "Password123!" }

    user.reload
    assert user.deleted?, "expired-token restore attempt must NOT clear deleted_at"
    assert_response :gone
  end

  test "POST /account/restore signs out a different currently-signed-in user before restoring the target account" do
    user_a = make_user # the person currently signed in
    user_b = make_user # the person whose link is being clicked
    plain_token = user_b.soft_delete!

    sign_in user_a

    post account_restoration_path, params: { token: plain_token, current_password: "Password123!" }

    assert_response :redirect
    user_b.reload
    refute user_b.deleted?, "target account must be restored"

    # Positively assert the active warden session is user_b's, not user_a's.
    # Devise stores the signed-in user as
    #   session["warden.user.user.key"] == [[user_id], <salt>]
    # We unwrap the outer array (one scope), then the inner array (PK
    # array — composite-key safe), and check it's exactly user_b.id. A
    # nil here means the request returned us to the unauthenticated
    # state; equal-to-user_a.id means warden never swapped.
    session_key = session["warden.user.user.key"]
    refute_nil session_key, "active warden session is required after restore"
    signed_in_user_id = Array(session_key).first&.first
    assert_equal user_b.id, signed_in_user_id, "active warden session must be user_b after restore"
    refute_equal user_a.id, signed_in_user_id, "user_a's session must have been replaced"
  end

  test "POST /account/restore is single-use: re-using a successful token fails" do
    user = make_user
    plain_token = user.soft_delete!

    # First restore succeeds
    post account_restoration_path, params: { token: plain_token, current_password: "Password123!" }
    assert_response :redirect

    # Now soft-delete again to put the user back in pending state with a NEW token
    second_plain = user.reload.soft_delete!
    assert_not_equal plain_token, second_plain, "a fresh soft-delete must mint a new token"

    # Simulate "fresh visitor / attacker re-using a leaked old link" — clear
    # the test session so we hit the public endpoint cleanly. Without this,
    # Devise's session-active check from the prior sign_in interferes.
    reset!

    # The original token must no longer work (it doesn't match the new hash)
    post account_restoration_path, params: { token: plain_token, current_password: "Password123!" }
    assert_response :not_found
  end
end
