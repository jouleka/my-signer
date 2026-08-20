require "rails_helper"

RSpec.describe "Contacts", type: :request do
  describe "POST /contacts" do
    let(:valid_params) do
      {
        contact: {
          name: "Test User",
          email: "test@example.com",
          category: "bug",
          message: "Found a bug in the app"
        }
      }
    end

    it "sends an email and redirects with success message" do
      expect {
        post contacts_path, params: valid_params
      }.to have_enqueued_job(ActionMailer::MailDeliveryJob)

      expect(response).to redirect_to("/#contact")
      follow_redirect!
      expect(flash[:contact_notice]).to eq("Thanks for reaching out! We'll get back to you soon.")
    end

    it "redirects with error when name is missing" do
      post contacts_path, params: { contact: valid_params[:contact].except(:name) }

      expect(response).to redirect_to("/#contact")
      follow_redirect!
      expect(flash[:contact_alert]).to eq("Please fill in all required fields.")
    end

    it "redirects with error when email is missing" do
      post contacts_path, params: { contact: valid_params[:contact].except(:email) }

      expect(response).to redirect_to("/#contact")
      follow_redirect!
      expect(flash[:contact_alert]).to eq("Please fill in all required fields.")
    end

    it "redirects with error when category is missing" do
      post contacts_path, params: { contact: valid_params[:contact].except(:category) }

      expect(response).to redirect_to("/#contact")
      follow_redirect!
      expect(flash[:contact_alert]).to eq("Please fill in all required fields.")
    end

    it "redirects with error when message is missing" do
      post contacts_path, params: { contact: valid_params[:contact].except(:message) }

      expect(response).to redirect_to("/#contact")
      follow_redirect!
      expect(flash[:contact_alert]).to eq("Please fill in all required fields.")
    end

    # Without format validation, these strings would land verbatim in the
    # mailer's `reply_to:` header. Mail gem strips CR/LF so none of them
    # are header-injection, but each still re-routes operator replies to
    # whatever address the attacker controls. Reject upfront.
    [
      "not-an-email",
      "<script>alert(1)</script>@evil.example",
      "a@b.com\r\nBcc: x@y.example",
      "a@b.com Bcc: x@y.example",
      "@no-localpart.example",
      "no-at-sign.example"
    ].each do |bad_email|
      it "rejects malformed email #{bad_email.inspect} instead of routing operator replies to it" do
        bad_params = valid_params.deep_merge(contact: { email: bad_email })

        expect {
          post contacts_path, params: bad_params
        }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)

        expect(response).to redirect_to("/#contact")
        follow_redirect!
        expect(flash[:contact_alert]).to eq("Please enter a valid email address.")
      end
    end

    context "honeypot spam protection" do
      it "silently accepts but does not send email when honeypot is filled" do
        spam_params = valid_params.deep_merge(contact: { website: "http://spam.com" })

        expect {
          post contacts_path, params: spam_params
        }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)

        expect(response).to redirect_to("/#contact")
        follow_redirect!
        # Still shows success to not alert spammers
        expect(flash[:contact_notice]).to eq("Thanks for reaching out! We'll get back to you soon.")
      end
    end
  end
end
