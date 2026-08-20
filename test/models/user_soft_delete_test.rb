require "test_helper"

class UserSoftDeleteTest < ActiveSupport::TestCase
  # Build a confirmed, fully-active user. Devise's :confirmable would
  # otherwise leave new users with active_for_authentication? == false,
  # which would mask the soft-delete behavior we're trying to test.
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

  test "#soft_delete! sets deleted_at and a deletion token and returns the plain token" do
    user = make_user
    assert_nil user.deleted_at
    assert_nil user.deletion_token

    plain_token = user.soft_delete!

    assert user.reload.deleted_at.present?, "expected deleted_at to be set"
    assert user.deletion_token.present?, "expected deletion_token (hash) stored on the row"
    assert plain_token.is_a?(String) && plain_token.length >= 32, "soft_delete! should return a plain token >= 32 chars"
    refute_equal plain_token, user.deletion_token,
      "the column should hold a HASH of the token, not the plain token"
  end

  test "#deleted? reflects state" do
    user = make_user
    refute user.deleted?

    user.soft_delete!
    assert user.deleted?
  end

  test "#soft_delete! is idempotent: calling on an already-deleted user returns nil and preserves the original token" do
    user = make_user
    first_token = user.soft_delete!
    original_hash    = user.deletion_token
    original_deleted = user.deleted_at

    second_token = user.soft_delete!

    assert_nil second_token, "calling soft_delete! a second time should return nil"
    assert_equal original_hash,    user.reload.deletion_token, "deletion_token must not change on re-call"
    assert_equal original_deleted.to_i, user.deleted_at.to_i, "deleted_at must not change on re-call"
    assert_not_nil first_token
  end

  test "#restore! clears deleted_at and deletion_token" do
    user = make_user
    user.soft_delete!
    assert user.deleted?

    user.restore!

    assert_nil user.reload.deleted_at
    assert_nil user.deletion_token
    refute user.deleted?
  end

  test "#restore! on a non-deleted user is a no-op" do
    user = make_user
    refute user.deleted?

    assert_nothing_raised { user.restore! }
    refute user.reload.deleted?
  end

  test "User.find_by_deletion_token finds a soft-deleted user by plain token" do
    user = make_user
    plain_token = user.soft_delete!

    found = User.find_by_deletion_token(plain_token)

    assert_equal user, found
  end

  test "User.find_by_deletion_token returns nil for blank/invalid input" do
    user = make_user
    user.soft_delete!

    assert_nil User.find_by_deletion_token(nil)
    assert_nil User.find_by_deletion_token("")
    assert_nil User.find_by_deletion_token("not-a-real-token-xxxxxxxxxxxxxxxx")
  end

  test "User.find_by_deletion_token does NOT match an active (non-deleted) user even if token bytes collide" do
    user = make_user
    plain_token = user.soft_delete!
    user.restore!

    assert_nil User.find_by_deletion_token(plain_token),
      "after restore, the previously valid token must not resolve to this user"
  end

  test ".pending_deletion and .active_accounts scopes partition users by deleted_at" do
    active  = make_user
    deleted = make_user
    deleted.soft_delete!

    assert_includes User.pending_deletion, deleted
    refute_includes User.pending_deletion, active

    assert_includes User.active_accounts, active
    refute_includes User.active_accounts, deleted
  end

  test "#active_for_authentication? blocks Devise sign-in for soft-deleted users" do
    user = make_user
    assert user.active_for_authentication?

    user.soft_delete!

    refute user.active_for_authentication?,
      "soft-deleted users must not be allowed to authenticate"
  end

  test "#inactive_message returns :pending_deletion for soft-deleted users (so Devise renders the right flash)" do
    user = make_user
    user.soft_delete!

    assert_equal :pending_deletion, user.inactive_message
  end

  test "#regenerate_deletion_token! mints a fresh token, invalidates the old one, preserves deleted_at" do
    user = make_user
    first_plain = user.soft_delete!
    original_deleted_at = user.deleted_at

    new_plain = user.regenerate_deletion_token!(actor: user)

    assert_not_nil new_plain
    assert_not_equal first_plain, new_plain, "regenerated token must differ from the original"

    assert_nil User.find_by_deletion_token(first_plain),
      "the old token must no longer resolve to anyone after regeneration"
    assert_equal user, User.find_by_deletion_token(new_plain),
      "the new token must resolve to this user"

    assert_equal original_deleted_at.to_i, user.reload.deleted_at.to_i,
      "deleted_at must NOT be reset by regeneration (the 90-day countdown is preserved)"
  end

  test "#regenerate_deletion_token! raises on a non-deleted user" do
    user = make_user
    refute user.deleted?

    assert_raises(User::NotPendingDeletion) { user.regenerate_deletion_token!(actor: user) }
  end

  test "Devise email uniqueness blocks sign-up with the email of a soft-deleted user (the email stays reserved during the 90-day window)" do
    deleted = make_user(email: "reserved-#{SecureRandom.hex(4)}@example.test")
    deleted.soft_delete!

    duplicate = User.new(email: deleted.email, password: "Password123!", accepts_terms: "1")
    duplicate.skip_confirmation!

    refute duplicate.save, "a fresh sign-up with a soft-deleted user's email must fail"
    assert duplicate.errors[:email].any?, "the email error must surface (Devise :validatable)"
  end

  test "#soft_delete! revokes all of the user's API tokens (so a leaked token can't outlive deactivation)" do
    user = make_user
    org  = Organization.create!(name: "Org #{SecureRandom.hex(4)}", owner: user)
    token1, _plain1 = ApiToken.generate_for(user: user, organization: org, name: "t1")
    token2, _plain2 = ApiToken.generate_for(user: user, organization: org, name: "t2")
    refute token1.revoked?
    refute token2.revoked?

    user.soft_delete!

    [ token1, token2 ].each(&:reload)
    assert token1.revoked?, "token #1 must be revoked on soft_delete"
    assert token2.revoked?, "token #2 must be revoked on soft_delete"
    refute token1.active?
    refute token2.active?
    assert token1.revoked_at.present?
    assert token2.revoked_at.present?
  end

  test "User.from_omniauth does NOT mutate a soft-deleted user matched by (provider, uid)" do
    user = make_user(email: "om-pu-#{SecureRandom.hex(4)}@example.test")
    original_uid = "google-#{SecureRandom.hex(4)}"
    user.update!(provider: "google_oauth2", uid: original_uid, name: "Original Name")
    user.soft_delete!
    user.reload

    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: original_uid,
      info: { email: user.email, name: "Mutated Name", image: "https://example.com/avatar.png" },
      extra: { raw_info: { email_verified: true } }
    )

    returned = User.from_omniauth(auth)

    assert_equal user.id, returned.id, "expected the same soft-deleted row to be returned"
    user.reload
    assert_equal "google_oauth2", user.provider, "provider must not be mutated mid-grace-window"
    assert_equal original_uid, user.uid, "uid must not be mutated mid-grace-window"
    assert_equal "Original Name", user.name, "name must not be mutated mid-grace-window"
    assert_nil user.avatar_url, "avatar_url must not be back-filled mid-grace-window"
    refute returned.active_for_authentication?, "soft-deleted user must still fail the auth gate"
  end

  test "User.from_omniauth refuses to auto-link a soft-deleted user matched by email" do
    user = make_user(email: "om-em-#{SecureRandom.hex(4)}@example.test")
    user.soft_delete!
    snapshot_confirmed_at = user.reload.confirmed_at

    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "fresh-uid-#{SecureRandom.hex(4)}",
      info: { email: user.email, name: "Should Not Stick" },
      extra: { raw_info: { email_verified: true } }
    )

    returned = User.from_omniauth(auth)

    # The email-only-match path is the OAuth-takeover surface. Refusing
    # the link is the M1 fix — `nil` is what the controller branches on
    # to surface "this email already exists; sign in with password and
    # link from settings". The soft-delete posture is a strict subset of
    # that: refused for the same reason, plus the row stays frozen.
    assert_nil returned, "from_omniauth must refuse email-only auto-link"
    user.reload
    assert_nil user.provider, "blank provider must not be back-filled by the email-only-match path"
    assert_nil user.uid, "blank uid must not be back-filled by the email-only-match path"
    assert_equal snapshot_confirmed_at.to_i, user.confirmed_at.to_i,
      "confirmed_at must not be re-set by the email-only-match path"
  end

  test "User.from_omniauth refuses to auto-link any active email-matched user without (provider, uid) (M1: OAuth back-fill takeover)" do
    user = make_user(email: "om-active-#{SecureRandom.hex(4)}@example.test")
    refute user.deleted?, "this test covers the active (non-soft-deleted) variant"
    snapshot_confirmed_at = user.reload.confirmed_at

    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "attacker-google-sub-#{SecureRandom.hex(4)}",
      info: { email: user.email, name: "Attacker" },
      extra: { raw_info: { email_verified: true } }
    )

    returned = User.from_omniauth(auth)

    assert_nil returned, "auto-link must be refused even for active users"
    user.reload
    assert_nil user.provider, "provider must not be back-filled from a public OAuth callback"
    assert_nil user.uid, "uid must not be back-filled from a public OAuth callback"
    assert_equal snapshot_confirmed_at.to_i, user.confirmed_at.to_i
  end
end
