require "test_helper"

class BillingMailerAccountPendingDeletionTest < ActionMailer::TestCase
  test "renders to/subject/body with the plain restore token in both HTML and text parts" do
    user = User.new(email: "deleter@example.test", name: "Deleter")
    plain_token = "plain-abc123token-xxxxxxxxxxxxxxxxxxxx"
    deletes_at  = Date.new(2026, 8, 1)

    mail = BillingMailer.account_pending_deletion(
      user: user,
      restore_token: plain_token,
      deletes_at: deletes_at
    )

    assert_equal [ user.email ], mail.to
    assert_match(/account.*deletion/i, mail.subject)

    html_body = mail.html_part&.body&.to_s || mail.body.to_s
    text_body = mail.text_part&.body&.to_s || mail.body.to_s

    assert_match plain_token, html_body, "HTML email must include the plain restore token"
    assert_match plain_token, text_body, "Text email must include the plain restore token"
    assert_match "August 1, 2026", html_body, "deletes_at date should be formatted human-readably"
  end
end
