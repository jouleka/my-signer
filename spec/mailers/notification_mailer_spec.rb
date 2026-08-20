require "rails_helper"

RSpec.describe NotificationMailer, type: :mailer do
  let(:user) { create(:user, name: "Test User") }
  let(:organization) { create(:organization, owner: user, name: "Acme Inc") }

  describe "#sync_failed" do
    let(:mail) do
      described_class.sync_failed(
        user: user,
        credential_type: "App Store Connect Credential",
        organization: organization,
        error_message: "Invalid API key: key expired"
      )
    end

    it "renders the subject" do
      expect(mail.subject).to eq("Sync Failed: App Store Connect Credential for Acme Inc")
    end

    it "sends to the correct user" do
      expect(mail.to).to include(user.email)
    end

    it "includes the error message in the body" do
      expect(mail.html_part.body.to_s).to include("Invalid API key")
      expect(mail.text_part.body.to_s).to include("Invalid API key")
    end

    it "includes the organization name" do
      expect(mail.html_part.body.to_s).to include("Acme Inc")
    end
  end

  describe "#resource_revoked" do
    let(:cert) { create(:apple_certificate, organization: organization, name: "Distribution Cert") }

    let(:mail) do
      described_class.resource_revoked(
        user: user,
        resource: cert,
        resource_type_label: "Apple Certificate"
      )
    end

    it "renders the subject" do
      expect(mail.subject).to eq("Urgent: Apple Certificate 'Distribution Cert' has been revoked")
    end

    it "sends to the correct user" do
      expect(mail.to).to include(user.email)
    end

    it "includes the resource name in the body" do
      expect(mail.html_part.body.to_s).to include("Distribution Cert")
      expect(mail.text_part.body.to_s).to include("Distribution Cert")
    end
  end

  describe "#team_member_joined" do
    let(:new_member) { create(:user, name: "Jane Developer") }

    let(:mail) do
      described_class.team_member_joined(
        user: user,
        new_member: new_member,
        organization: organization
      )
    end

    it "renders the subject" do
      expect(mail.subject).to eq("Jane Developer joined Acme Inc")
    end

    it "sends to the correct user" do
      expect(mail.to).to include(user.email)
    end

    it "includes the new member's name in the body" do
      expect(mail.html_part.body.to_s).to include("Jane Developer")
      expect(mail.text_part.body.to_s).to include("Jane Developer")
    end

    it "uses email when new member has no name" do
      new_member.update!(name: nil)
      expect(mail.subject).to include(new_member.email)
    end
  end

  describe "#api_token_created" do
    let(:creator) { create(:user, name: "Bob Admin") }

    let(:mail) do
      described_class.api_token_created(
        user: user,
        creator: creator,
        token_name: "CI Deploy Token",
        organization: organization
      )
    end

    it "renders the subject" do
      expect(mail.subject).to eq("New API Token created in Acme Inc")
    end

    it "sends to the correct user" do
      expect(mail.to).to include(user.email)
    end

    it "includes the token name in the body" do
      expect(mail.html_part.body.to_s).to include("CI Deploy Token")
      expect(mail.text_part.body.to_s).to include("CI Deploy Token")
    end

    it "includes the creator's name" do
      expect(mail.html_part.body.to_s).to include("Bob Admin")
    end
  end

  describe "#sync_completed" do
    let(:mail) do
      described_class.sync_completed(
        user: user,
        organization: organization,
        changes_summary: [ "2 new apple certificates", "1 new apple provisioning profile" ]
      )
    end

    it "renders the subject" do
      expect(mail.subject).to eq("Sync completed with changes for Acme Inc")
    end

    it "sends to the correct user" do
      expect(mail.to).to include(user.email)
    end

    it "includes the changes in the body" do
      expect(mail.html_part.body.to_s).to include("2 new apple certificates")
      expect(mail.text_part.body.to_s).to include("2 new apple certificates")
    end
  end
end
