require "rails_helper"

RSpec.describe Aso::RankAlertMailer, type: :mailer do
  let(:org)  { create(:organization, name: "Acme") }
  let(:user) { create(:user) }
  let(:app)  { create(:apple_app, organization: org) }
  let(:tk)   { create(:tracked_keyword, apple_app: app, keyword: "photo editor") }
  let(:tkc)  { create(:tracked_keyword_country, tracked_keyword: tk, country: "us", current_rank: 8) }

  let(:movement) do
    Aso::RankMovement.new(tkc: tkc, current: 8, week_ago: 25)
  end

  describe "#weekly_digest" do
    subject(:mail) do
      described_class.weekly_digest(user: user, organization: org, movements: [ movement ])
    end

    it "sends to the user's email" do
      expect(mail.to).to eq([ user.email ])
    end

    it "includes the organization name in the subject" do
      expect(mail.subject).to include("Acme")
    end

    it "includes the keyword and rank change in the HTML body" do
      body = mail.html_part.body.to_s
      expect(body).to include("photo editor")
      expect(body).to include("#8")
      expect(body).to include("#25")
    end

    it "renders empty state when no movements" do
      empty_mail = described_class.weekly_digest(user: user, organization: org, movements: [])
      expect(empty_mail.html_part.body.to_s).to include("No significant rank changes")
    end
  end

  describe "header injection hardening" do
    it "strips CR/LF from org.name in Subject" do
      org.update_column(:name, "Evil Co\r\nBcc: attacker@example.com")
      mail = described_class.weekly_digest(user: user, organization: org, movements: [])
      expect(mail.subject).not_to include("\r")
      expect(mail.subject).not_to include("\n")
      expect(mail.subject).not_to include("Bcc:")
    end

    it "truncates overly long org names" do
      long_name = "X" * 500
      org.update_column(:name, long_name)
      mail = described_class.weekly_digest(user: user, organization: org, movements: [])
      # subject has "[MySigner] Weekly keyword rank changes for " + truncated name
      expect(mail.subject.length).to be < 150
    end
  end
end
