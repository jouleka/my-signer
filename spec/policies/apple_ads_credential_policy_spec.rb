require "rails_helper"
require "pundit/rspec"

RSpec.describe AppleAdsCredentialPolicy do
  subject { described_class }

  # :team_plan so the org supports multiple memberships (Pro caps at 1 seat).
  let(:owner_user) { create(:user, :team_plan) }
  let(:org) { create(:organization, owner: owner_user) }
  let(:credential) { create(:apple_ads_credential, organization: org) }

  let(:admin_member) do
    u = create(:user)
    org.memberships.create!(user: u, role: :admin)
    u
  end

  let(:developer_member) do
    u = create(:user)
    org.memberships.create!(user: u, role: :developer)
    u
  end

  let(:viewer_member) do
    u = create(:user)
    org.memberships.create!(user: u, role: :viewer)
    u
  end

  let(:outsider) { create(:user, :pro_plan) }

  permissions :new?, :create?, :edit?, :update?, :destroy? do
    it "permits org owner (admin role)" do
      expect(subject).to permit(owner_user, credential)
    end

    it "permits admin members" do
      expect(subject).to permit(admin_member, credential)
    end

    it "DENIES developer members" do
      expect(subject).not_to permit(developer_member, credential)
    end

    it "DENIES viewer members" do
      expect(subject).not_to permit(viewer_member, credential)
    end

    it "DENIES outsiders" do
      expect(subject).not_to permit(outsider, credential)
    end

    it "DENIES unauthenticated" do
      expect(subject).not_to permit(nil, credential)
    end
  end

  context "passing an Organization record (for new?/create? on a cred that doesn't exist yet)" do
    permissions :new?, :create? do
      it "permits org owner" do
        expect(subject).to permit(owner_user, org)
      end

      it "DENIES developer members" do
        expect(subject).not_to permit(developer_member, org)
      end

      it "DENIES outsiders" do
        expect(subject).not_to permit(outsider, org)
      end
    end
  end
end
