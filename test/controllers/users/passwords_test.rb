require "test_helper"

# Covers the soft-delete defense in Users::PasswordsController#update.
# Devise's default `reset_password_by_token` writes the new password
# BEFORE branching on `active_for_authentication?`, then unconditionally
# calls `sign_in(resource_name, resource)`. Two problems for a
# soft-deleted user:
#
#   1. Response-shape oracle (flash key differs by active state)
#   2. Delayed-takeover surface: an attacker with a leaked reset token
#      can write a password to a row that's pending purge, and when
#      the user later restores the account within the 90-day window
#      the attacker holds working credentials.
#
# The override resolves the user from the token and short-circuits to
# the generic invalid-token UX if the resolved row is soft-deleted.
class Users::PasswordsTest < ActionDispatch::IntegrationTest
  def make_user(password: "OriginalPassword123!", **overrides)
    user = User.new({
      email: "pwd-#{SecureRandom.hex(6)}@example.test",
      password: password,
      accepts_terms: "1"
    }.merge(overrides))
    user.skip_confirmation!
    user.save!
    user
  end

  def issue_reset_token_for(user)
    # Devise's reset-token flow: generate a plain token, store the
    # hashed form on the user row. Same shape as what
    # `send_reset_password_instructions` produces, minus the mailer.
    raw_token, db_token = Devise.token_generator.generate(User, :reset_password_token)
    user.update_columns(
      reset_password_token: db_token,
      reset_password_sent_at: Time.current
    )
    raw_token
  end

  test "PATCH /users/password with valid token for ACTIVE user resets the password" do
    user = make_user
    raw_token = issue_reset_token_for(user)
    new_password = "BrandNewPassword456!"

    patch user_password_path, params: {
      user: {
        reset_password_token: raw_token,
        password: new_password,
        password_confirmation: new_password
      }
    }

    user.reload
    assert user.valid_password?(new_password),
      "active user's password must update via the standard reset flow"
    assert_response :redirect
  end

  test "PATCH /users/password with valid token for a SOFT-DELETED user does NOT change the password and does NOT leak the deletion state" do
    user = make_user(password: "OriginalPassword123!")
    raw_token = issue_reset_token_for(user)
    user.soft_delete!

    patch user_password_path, params: {
      user: {
        reset_password_token: raw_token,
        password: "AttackerChosen789!",
        password_confirmation: "AttackerChosen789!"
      }
    }

    user.reload

    # 1) Password write must NOT have occurred. This is the
    # delayed-takeover defense -- if the user later restores, the
    # attacker who held the leaked token must NOT have working creds.
    assert user.valid_password?("OriginalPassword123!"),
      "soft-deleted user's password must NOT be overwritten by a stale reset token"
    refute user.valid_password?("AttackerChosen789!"),
      "the attacker-chosen password must have been rejected before the bcrypt write"

    # 2) Reset token must NOT have been consumed -- it's irrelevant
    # anyway since send_reset_password_instructions blocks new ones
    # during the grace window, but a legitimate restore-then-reset path
    # should be able to re-issue. Consumed/not-consumed here is
    # implementation-detail; the password not changing is what matters.

    # 3) Response shape must match Devise's standard "invalid token"
    # reply: 422 + render :edit + reset_password_token error. The form
    # must also round-trip the submitted token in its hidden field --
    # Devise's `reset_password_by_token` does that on the invalid-token
    # branch, so if our override didn't we'd be leaking soft-delete
    # state via the rendered HTML.
    assert_response :unprocessable_content
    assert_nil session["warden.user.user.key"],
      "soft-deleted user must NOT be signed in via the password reset callback"
    refute_includes flash[:notice].to_s.downcase, "updated",
      "soft-deleted user must NOT see the 'password updated' success flash"
    assert_includes response.body, raw_token,
      "the form's hidden reset_password_token field must round-trip the submitted token (matches Devise's invalid-token render)"
  end

  test "PATCH /users/password with INVALID token for a soft-deleted user uses the same response shape (no oracle differential)" do
    user = make_user
    user.soft_delete!
    garbage_token = "garbage-token-not-real-#{SecureRandom.hex(8)}"

    # This is the control for the previous test. Same set of response
    # properties asserted: status, session, no success-flash, and the
    # hidden token round-trip. If any of these differs from the
    # valid-token-soft-deleted case, an attacker probing the endpoint
    # with the two inputs could tell the cases apart from the
    # response body alone.
    patch user_password_path, params: {
      user: {
        reset_password_token: garbage_token,
        password: "Whatever123!",
        password_confirmation: "Whatever123!"
      }
    }

    assert_response :unprocessable_content
    assert_nil session["warden.user.user.key"]
    refute_includes flash[:notice].to_s.downcase, "updated"
    assert_includes response.body, garbage_token,
      "Devise's stock invalid-token render round-trips the submitted token; the override must match for no differential"
  end
end
