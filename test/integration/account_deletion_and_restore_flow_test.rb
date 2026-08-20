require "test_helper"

class AccountDeletionAndRestoreFlowTest < ActionDispatch::IntegrationTest
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

  test "full delete + restore loop works end-to-end" do
    user = make_user(password: "MySecret123!")
    sign_in user

    # 1. User requests deletion
    delete user_registration_path, params: { current_password: "MySecret123!" }

    assert User.find_by(id: user.id), "row must still exist (soft-delete only)"
    user.reload
    assert user.deleted?
    assert user.deletion_token.present?

    # 2. The pending-deletion email was enqueued. We perform the queued jobs
    #    inline so we can inspect the rendered mail.
    perform_enqueued_jobs

    delivery = ActionMailer::Base.deliveries.find { |m| m.subject =~ /scheduled for deletion/i }
    refute_nil delivery, "expected an account_pending_deletion email to be delivered"

    # 3. Extract the restore token from the email body. We wrote both an
    #    HTML and text part, both of which contain the URL. We pull from
    #    the text part for cleanliness.
    text_body = delivery.text_part&.body&.to_s || delivery.body.to_s
    match = text_body.match(/account\/restore\?token=([^\s)]+)/)
    refute_nil match, "expected a restore URL with a token in the email"
    plain_token = CGI.unescape(match[1])

    # 4. The user clicks the restore link
    reset!  # mimic "different browser session"
    get account_restoration_path, params: { token: plain_token }
    assert_response :success

    # 5. The user confirms the restore. Re-auth is required (M2 fix —
    # the link alone is no longer a bearer credential): supply the
    # account password so `valid_password?` accepts the request.
    post account_restoration_path, params: { token: plain_token, current_password: "MySecret123!" }
    assert_response :redirect

    # 6. User is restored and can sign in normally
    user.reload
    refute user.deleted?
    assert_nil user.deletion_token

    reset!
    post user_session_path, params: { user: { email: user.email, password: "MySecret123!" } }
    assert_response :redirect, "restored user must be able to sign in normally"
  end

  test "soft-deleted user cannot sign in" do
    user = make_user(password: "MySecretLongPassword123!")
    user.soft_delete!

    post user_session_path, params: { user: { email: user.email, password: "MySecretLongPassword123!" } }

    # Devise re-renders the sign-in page (HTTP 200) and the user is
    # NOT signed in. The flash message must NOT reveal "pending
    # deletion" -- that would be an oracle for an attacker probing
    # which emails are in their 90-day deletion window (high-value
    # signal for phishing the restoration email). The
    # devise.failure.pending_deletion key is intentionally mapped to
    # the same generic copy as not_found_in_database.
    assert_no_match(/dashboard/i, response.body) if response.body.present?
    refute_includes flash[:alert].to_s, "pending deletion"
    assert_includes flash[:alert].to_s, "Invalid"
  end
end
