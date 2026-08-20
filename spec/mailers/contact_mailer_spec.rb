require "rails_helper"

RSpec.describe ContactMailer, type: :mailer do
  describe "#new_message" do
    let(:mail) do
      described_class.new_message(
        name: "John Doe",
        email: "john@example.com",
        category: "bug",
        message: "Found a bug when uploading to TestFlight"
      )
    end

    it "renders the subject with category and name" do
      expect(mail.subject).to eq("[MySigner Contact] Bug Report from John Doe")
    end

    it "sends to the configured contact email" do
      # Uses configured email from credentials, or falls back to default
      expect(mail.to.first).to match(/@/)
    end

    it "sets reply-to as the sender's email" do
      expect(mail.reply_to).to include("john@example.com")
    end

    it "includes the message in the body" do
      expect(mail.html_part.body.to_s).to include("Found a bug when uploading to TestFlight")
      expect(mail.text_part.body.to_s).to include("Found a bug when uploading to TestFlight")
    end

    it "includes the sender's name in the body" do
      expect(mail.html_part.body.to_s).to include("John Doe")
      expect(mail.text_part.body.to_s).to include("John Doe")
    end

    it "includes the category badge" do
      expect(mail.html_part.body.to_s).to include("Bug Report")
    end

    context "with different categories" do
      %w[bug feature question feedback other].each do |category|
        it "handles #{category} category" do
          mail = described_class.new_message(
            name: "Test",
            email: "test@example.com",
            category: category,
            message: "Test message"
          )
          expect(mail.subject).to be_present
        end
      end
    end

    context "with HTML-injection payloads in the email field" do
      # The contact form has no server-side email validation beyond
      # `present?` (see ContactsController#create), so an attacker can
      # submit any string as `email`. Both the visible link label and
      # the `href="mailto:..."` attribute are attacker-controlled inputs
      # to `ms_link`. Without escaping at the helper layer they would
      # render as live HTML in the operator's mailbox.
      let(:payload) { %q{</a><svg/onload=alert(1)>"@evil.example/x.com} }
      let(:mail) do
        described_class.new_message(
          name: "John Doe",
          email: payload,
          category: "bug",
          message: "Hello"
        )
      end

      it "does not render the payload as live HTML in the body" do
        body = mail.html_part.body.to_s
        expect(body).not_to include("<svg/onload")
        expect(body).not_to include("</a><svg")
      end

      it "does not let the payload break out of the href attribute" do
        body = mail.html_part.body.to_s
        # The escaped form must contain the entity-encoded angle bracket
        # (`&lt;` or `&amp;lt;` depending on layer), and must NOT contain
        # the bare `>` or `"` that would close the anchor's href quote.
        expect(body).to include(ERB::Util.h(payload))
      end
    end
  end
end
