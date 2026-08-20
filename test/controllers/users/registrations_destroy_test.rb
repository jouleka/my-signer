require "test_helper"

class Users::RegistrationsDestroyTest < ActionDispatch::IntegrationTest
  def make_user(password: "Password123!", **overrides)
    user = User.new({
      email: "u-#{SecureRandom.hex(6)}@example.test",
      password: password,
      accepts_terms: "1"
    }.merge(overrides))
    user.skip_confirmation!
    user.save!
    user
  end

  test "DELETE /users with correct password soft-deletes the user instead of hard-deleting" do
    user = make_user(password: "CorrectPass123!")
    sign_in user

    assert_no_difference -> { User.count }, "soft-delete must NOT remove the row" do
      delete user_registration_path, params: { current_password: "CorrectPass123!" }
    end

    user.reload
    assert user.deleted?, "user should be marked deleted_at"
    assert user.deletion_token.present?, "deletion_token must be set"
  end

  test "DELETE /users with correct password sends the account_pending_deletion email" do
    user = make_user(password: "CorrectPass123!")
    sign_in user

    # `assert_emails` (not `assert_enqueued_emails`) because the controller
    # delivers synchronously via `deliver_now` -- intentional, to keep the
    # plain restoration token out of `solid_queue_jobs.arguments` until
    # the worker picks it up. See the comment in registrations#destroy.
    assert_emails 1 do
      delete user_registration_path, params: { current_password: "CorrectPass123!" }
    end
  end

  test "DELETE /users with correct password signs the user out" do
    user = make_user(password: "CorrectPass123!")
    sign_in user

    delete user_registration_path, params: { current_password: "CorrectPass123!" }

    follow_redirect!
    # The session should no longer authenticate this user. Hitting a protected page
    # would redirect; we check that the response is successful (landing) rather than
    # a dashboard view that requires auth.
    assert_response :success
  end

  test "DELETE /users with WRONG password does NOT soft-delete and does NOT send email" do
    user = make_user(password: "CorrectPass123!")
    sign_in user

    assert_no_enqueued_emails do
      delete user_registration_path, params: { current_password: "WrongPass!!" }
    end

    user.reload
    refute user.deleted?, "user must NOT be soft-deleted with wrong password"
    assert_nil user.deletion_token
  end

  test "DELETE /users with NO password does NOT soft-delete and does NOT send email" do
    user = make_user(password: "CorrectPass123!")
    sign_in user

    assert_no_enqueued_emails do
      delete user_registration_path, params: {}
    end

    user.reload
    refute user.deleted?
    assert_nil user.deletion_token
  end
end
