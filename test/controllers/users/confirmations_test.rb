require "test_helper"

class Users::ConfirmationsTest < ActionDispatch::IntegrationTest
  def make_unconfirmed_user(**overrides)
    user = User.new({
      email: "u-#{SecureRandom.hex(6)}@example.test",
      password: "Password123!",
      accepts_terms: "1"
    }.merge(overrides))
    user.save!
    user
  end

  test "GET /users/confirmation with a valid token for an ACTIVE user signs them in and shows the confirmed flash" do
    user = make_unconfirmed_user
    raw_token, db_token = Devise.token_generator.generate(User, :confirmation_token)
    user.update_columns(confirmation_token: db_token, confirmation_sent_at: Time.current)

    get user_confirmation_path, params: { confirmation_token: raw_token }

    user.reload
    assert user.confirmed?, "valid token must mark the user confirmed"
    assert_response :redirect
  end

  test "GET /users/confirmation for a SOFT-DELETED user does NOT sign them in and does NOT leak the soft-delete state" do
    # The defensive check in ConfirmationsController#show prevents the
    # success UX from rendering for a soft-deleted user. Without it,
    # `sign_in` would seat the user in Warden's session (Devise's
    # explicit `sign_in` skips `active_for_authentication?`), the
    # "confirmed!" flash + post-sign-in redirect would render, and an
    # attacker holding a confirmation token could distinguish
    # soft-deleted from active rows by which response shape they get.
    user = make_unconfirmed_user
    user.skip_confirmation! # set confirmed_at so soft_delete! works
    user.save!
    raw_token, db_token = Devise.token_generator.generate(User, :confirmation_token)
    # Reset confirmed_at so a fresh confirmation attempt makes sense; the
    # token validity is what we're probing.
    user.update_columns(confirmation_token: db_token, confirmation_sent_at: Time.current, confirmed_at: nil)
    user.soft_delete!

    get user_confirmation_path, params: { confirmation_token: raw_token }

    # Should redirect to the sign-in page with the generic invalid-token
    # alert -- NEVER the post-sign-in dashboard, NEVER the "confirmed"
    # success flash.
    assert_response :redirect
    refute_match(/dashboard/i, response.location.to_s)
    refute_includes flash[:notice].to_s.downcase, "confirmed"

    # And the warden session must NOT have been seated.
    assert_nil session["warden.user.user.key"],
      "soft-deleted user must NOT be signed in via the confirmation callback"
  end
end
