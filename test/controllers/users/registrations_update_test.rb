require "test_helper"

# Covers the security boundary on PATCH /users (Devise account update):
# the form's permitted keys include `provider` and `uid` ONLY so the
# settings-page "Disconnect SSO" modal can blank them. Setting either
# to a specific value via this endpoint would let any logged-in attacker
# claim a victim's (provider, uid) pair and hijack the victim's next
# OAuth sign-in (User.from_omniauth resolves by find_by(provider:, uid:)
# before falling back to email).
class Users::RegistrationsUpdateTest < ActionDispatch::IntegrationTest
  PASSWORD = "Password123!".freeze

  def make_user(**overrides)
    user = User.new({
      email: "u-#{SecureRandom.hex(6)}@example.test",
      password: PASSWORD,
      accepts_terms: "1"
    }.merge(overrides))
    user.skip_confirmation!
    user.save!
    user
  end

  test "PATCH /users IGNORES non-blank provider/uid (cannot mass-assign attacker's chosen identity)" do
    attacker = make_user
    sign_in attacker

    patch user_registration_path, params: {
      user: {
        provider: "google_oauth2",
        uid: "victim-google-sub-12345",
        current_password: PASSWORD
      }
    }

    attacker.reload
    assert_nil attacker.provider, "provider must remain unset; the form must not mass-assign it"
    assert_nil attacker.uid, "uid must remain unset; the form must not mass-assign it"
  end

  test "PATCH /users IGNORES non-blank provider/uid even when only one is set" do
    attacker = make_user
    sign_in attacker

    patch user_registration_path, params: {
      user: {
        provider: "github",
        uid: "",
        current_password: PASSWORD
      }
    }

    attacker.reload
    assert_nil attacker.provider, "provider must not be settable in isolation"
  end

  test "PATCH /users with blank provider/uid still works (SSO disconnect path)" do
    user = make_user
    user.update!(provider: "google_oauth2", uid: "linked-uid-#{SecureRandom.hex(4)}")
    sign_in user

    patch user_registration_path, params: {
      user: {
        provider: "",
        uid: "",
        avatar_url: "",
        current_password: PASSWORD
      }
    }

    user.reload
    assert user.provider.blank?, "blank provider submission must clear the linked SSO provider"
    assert user.uid.blank?, "blank uid submission must clear the linked SSO uid"
  end
end
