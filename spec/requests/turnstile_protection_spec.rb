require "rails_helper"
require "webmock/rspec"

RSpec::Matchers.define_negated_matcher :not_change, :change
RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job

RSpec.describe "Cloudflare Turnstile protection", type: :request do
  let(:siteverify_url) { "https://challenges.cloudflare.com/turnstile/v0/siteverify" }
  let(:secret) { "spec-secret-not-a-real-key" }
  let(:failure_message) { TurnstileProtection::TURNSTILE_FAILURE_MESSAGE }
  let(:password) { "SecurePassword123!" }
  let!(:user) { User.create!(email: "turnstile@example.com", password: password, confirmed_at: Time.current) }

  def stub_siteverify(success:, error_codes: [])
    stub_request(:post, siteverify_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { success: success, "error-codes" => error_codes }.to_json)
  end

  context "with a real (non-test) secret configured" do
    before { allow(TurnstileVerifier).to receive(:secret_key).and_return(secret) }

    describe "POST /users/sign_in" do
      it "signs in when siteverify accepts the token, forwarding CF-Connecting-IP" do
        stub = stub_siteverify(success: true)

        post user_session_path,
             params: { user: { email: user.email, password: password }, "cf-turnstile-response" => "good-token" },
             headers: { "CF-Connecting-IP" => "203.0.113.7" }

        expect(stub.with(body: { "secret" => secret, "response" => "good-token", "remoteip" => "203.0.113.7" })).to have_been_requested
        expect(response).to have_http_status(:see_other).or have_http_status(:found)
        expect(request.env["warden"].authenticated?(:user)).to be(true)
      end

      it "re-renders the form with 422 and does not authenticate when siteverify rejects the token" do
        stub_siteverify(success: false, error_codes: [ "invalid-input-response" ])

        post user_session_path,
             params: { user: { email: user.email, password: password }, "cf-turnstile-response" => "bad-token" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(ERB::Util.html_escape(failure_message))
        expect(response.body).to include('data-controller="turnstile"')
        # Rendering the layout must not have run the params strategy either.
        expect(request.env["warden"].authenticated?(:user)).to be(false)
        get settings_path
        expect(response).to redirect_to(new_user_session_path)
      end

      it "rejects a missing token without calling Cloudflare" do
        post user_session_path, params: { user: { email: user.email, password: password } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(a_request(:post, siteverify_url)).not_to have_been_made
      end

      it "fails closed (422, not 500) when siteverify is unreachable" do
        stub_request(:post, siteverify_url).to_timeout

        post user_session_path,
             params: { user: { email: user.email, password: password }, "cf-turnstile-response" => "token" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(ERB::Util.html_escape(failure_message))
      end
    end

    describe "POST /users (sign up)" do
      it "does not create the account when verification fails" do
        stub_siteverify(success: false)

        expect {
          post user_registration_path, params: {
            user: { email: "new@example.com", password: password, password_confirmation: password, accepts_terms: "1" },
            "cf-turnstile-response" => "bad-token"
          }
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(ERB::Util.html_escape(failure_message))
      end

      it "creates the account when verification succeeds" do
        stub_siteverify(success: true)

        expect {
          post user_registration_path, params: {
            user: { email: "new@example.com", password: password, password_confirmation: password, accepts_terms: "1" },
            "cf-turnstile-response" => "good-token"
          }
        }.to change(User, :count).by(1)
      end
    end

    {
      "password reset" => -> { user_password_path },
      "confirmation resend" => -> { user_confirmation_path },
      "unlock resend" => -> { user_unlock_path }
    }.each do |label, path|
      describe "POST #{label}" do
        it "re-renders with 422 and sends no email when verification fails" do
          stub_siteverify(success: false)

          expect {
            post instance_exec(&path), params: { user: { email: user.email }, "cf-turnstile-response" => "bad-token" }
          }.to not_change { ActionMailer::Base.deliveries.size }
            .and not_have_enqueued_job(ActionMailer::MailDeliveryJob)

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include(ERB::Util.html_escape(failure_message))
        end
      end
    end

    it "skips the challenge for an already signed-in user (Settings → Verify email)" do
      sign_in user

      post user_confirmation_path, params: { user: { email: user.email } }

      expect(response).not_to have_http_status(:unprocessable_content)
      expect(a_request(:post, siteverify_url)).not_to have_been_made
    end

    describe "POST /contacts" do
      let(:contact_params) do
        { contact: { name: "Test", email: "test@example.com", category: "bug", message: "Hi" } }
      end

      it "redirects with an alert and sends nothing when verification fails" do
        stub_siteverify(success: false)

        expect {
          post contacts_path, params: contact_params.merge("cf-turnstile-response" => "bad-token")
        }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)

        expect(response).to redirect_to("/#contact")
        follow_redirect!
        expect(flash[:contact_alert]).to eq(failure_message)
      end

      it "renders the alert via turbo stream when verification fails" do
        stub_siteverify(success: false)

        post contacts_path, params: contact_params.merge("cf-turnstile-response" => "bad-token"),
                            headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("contact-form-messages", ERB::Util.html_escape(failure_message))
      end

      it "delivers the message when verification succeeds" do
        stub_siteverify(success: true)

        expect {
          post contacts_path, params: contact_params.merge("cf-turnstile-response" => "good-token")
        }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
      end
    end
  end

  context "with the Cloudflare always-pass test secret (default in test env)" do
    it "passes locally without calling Cloudflare" do
      expect(TurnstileVerifier.secret_key).to eq(TurnstileVerifier::TEST_SECRET_KEY)

      post user_session_path, params: { user: { email: user.email, password: password } }

      expect(a_request(:post, siteverify_url)).not_to have_been_made
      expect(request.env["warden"].authenticated?(:user)).to be(true)
    end
  end

  it "renders the widget inside the resend form on the post-signup check-email page" do
    post user_registration_path, params: {
      user: { email: "fresh@example.com", password: password, password_confirmation: password, accepts_terms: "1" }
    }
    follow_redirect!

    expect(response.body).to include('name="user[email]"', 'value="check_email"', 'data-controller="turnstile"')
  end

  context "when no secret is configured" do
    before { allow(TurnstileVerifier).to receive(:secret_key).and_return(nil) }

    it "fails closed" do
      post user_session_path,
           params: { user: { email: user.email, password: password }, "cf-turnstile-response" => "token" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(a_request(:post, siteverify_url)).not_to have_been_made
    end
  end

  it "renders the widget with the configured site key on the public forms" do
    [ new_user_session_path, new_user_registration_path, new_user_password_path,
      new_user_confirmation_path, new_user_unlock_path ].each do |path|
      get path
      expect(response.body).to include(%(data-turnstile-site-key-value="#{TurnstileVerifier::TEST_SITE_KEY}")), path
    end
  end
end
