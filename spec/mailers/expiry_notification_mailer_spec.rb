require "rails_helper"

RSpec.describe ExpiryNotificationMailer, type: :mailer do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:cert) { create(:apple_certificate, organization: organization, name: "Dev Certificate") }

  describe "#expiry_warning" do
    context "with days remaining > 0" do
      let(:mail) do
        described_class.expiry_warning(user: user, resource: cert, days_remaining: 7)
      end

      it "renders the subject with days remaining" do
        expect(mail.subject).to eq("Action Required: Apple Certificate 'Dev Certificate' expires in 7 days")
      end

      it "sends to the correct user" do
        expect(mail.to).to include(user.email)
      end

      it "includes the resource name in the body" do
        expect(mail.html_part.body.to_s).to include("Dev Certificate")
        expect(mail.text_part.body.to_s).to include("Dev Certificate")
      end
    end

    context "when expires today (day 0)" do
      let(:mail) do
        described_class.expiry_warning(user: user, resource: cert, days_remaining: 0)
      end

      it "renders the subject with 'expires today'" do
        expect(mail.subject).to eq("Action Required: Apple Certificate 'Dev Certificate' expires today")
      end
    end
  end

  describe "#expired_notice" do
    let(:mail) do
      described_class.expired_notice(user: user, resource: cert)
    end

    it "renders the subject with 'has expired'" do
      expect(mail.subject).to eq("Urgent: Apple Certificate 'Dev Certificate' has expired")
    end

    it "sends to the correct user" do
      expect(mail.to).to include(user.email)
    end

    it "includes the resource name in the body" do
      expect(mail.html_part.body.to_s).to include("Dev Certificate")
      expect(mail.text_part.body.to_s).to include("Dev Certificate")
    end

    it "includes the resource type" do
      expect(mail.html_part.body.to_s).to include("Apple Certificate")
    end
  end
end
