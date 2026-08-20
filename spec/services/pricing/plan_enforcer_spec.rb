require "rails_helper"

RSpec.describe Pricing::PlanEnforcer do
  describe "#apply!" do
    it "blocks newer owned organizations that exceed the current plan limit" do
      owner = create(:user, :team_plan)
      organizations = Array.new(5) { |index| create(:organization, owner: owner, name: "Org #{index + 1}") }

      owner.update!(plan_tier: :pro)
      described_class.new(owner).apply!

      expect(organizations.first(3).map(&:reload).map(&:access_state)).to all(eq("active"))
      expect(organizations.last(2).map(&:reload).map(&:access_state)).to all(eq("plan_blocked"))
      expect(organizations.last(2).map(&:access_block_reason)).to all(eq("owned_organization_limit"))
    end

    it "restores access when the owner upgrades again" do
      owner = create(:user, :team_plan)
      organizations = Array.new(5) { |index| create(:organization, owner: owner, name: "Org #{index + 1}") }

      owner.update!(plan_tier: :pro)
      described_class.new(owner).apply!
      owner.update!(plan_tier: :team)

      described_class.new(owner).apply!

      expect(organizations.map(&:reload).map(&:access_state)).to all(eq("active"))
      expect(organizations.map(&:access_blocked_at)).to all(be_nil)
    end

    it "clears an inaccessible last organization reference" do
      owner = create(:user, :team_plan)
      organizations = Array.new(5) { |index| create(:organization, owner: owner, name: "Org #{index + 1}") }
      owner.update_column(:last_organization_id, organizations.last.id)

      owner.update!(plan_tier: :pro)
      described_class.new(owner).apply!

      expect(owner.reload.last_organization_id).to eq(organizations.first.id)
    end

    it "prefers the oldest accessible owned organization over shared memberships when normalizing the last organization" do
      owner = create(:user, :team_plan)
      shared_owner = create(:user, :team_plan)
      shared_organization = create(:organization, owner: shared_owner, name: "Shared Org", created_at: 10.days.ago)
      create(:membership, organization: shared_organization, user: owner, role: :developer)
      organizations = Array.new(5) do |index|
        create(:organization, owner: owner, name: "Org #{index + 1}", created_at: (5 - index).days.ago)
      end
      owner.update_column(:last_organization_id, organizations.last.id)

      owner.update!(plan_tier: :pro)
      described_class.new(owner).apply!

      expect(owner.reload.last_organization_id).to eq(organizations.first.id)
    end

    it "applies free-plan organization limits after a downgrade" do
      owner = create(:user, :team_plan)
      organizations = Array.new(4) { |index| create(:organization, owner: owner, name: "Org #{index + 1}") }

      owner.update!(plan_tier: :free)
      described_class.new(owner).apply!

      expect(organizations.first.reload.access_state).to eq("active")
      expect(organizations.drop(1).map(&:reload).map(&:access_state)).to all(eq("plan_blocked"))
    end

    it "does not block organizations the user only belongs to" do
      owner = create(:user, :team_plan)
      external_owner = create(:user, :team_plan)
      shared_organization = create(:organization, owner: external_owner, name: "Shared Org")
      create(:membership, organization: shared_organization, user: owner, role: :developer)
      Array.new(5) { |index| create(:organization, owner: owner, name: "Owned Org #{index + 1}") }

      owner.update!(plan_tier: :pro)
      described_class.new(owner).apply!

      expect(shared_organization.reload.access_state).to eq("active")
    end

    it "skips access-state writes when the rollout migration is not available yet" do
      owner = create(:user, :team_plan)
      create(:organization, owner: owner, name: "Org 1")

      allow(Organization).to receive(:access_state_supported?).and_return(false)

      expect {
        described_class.new(owner).apply!
      }.not_to raise_error
    end
  end
end
