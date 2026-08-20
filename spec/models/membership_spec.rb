require "rails_helper"

RSpec.describe Membership, type: :model do
  describe "seat limits" do
    it "blocks extra members when the seat cap is reached" do
      owner = create(:user, :pro_plan)
      organization = create(:organization, owner: owner)

      # Pro plan has 1 seat (owner only), so any additional member is blocked
      extra_membership = organization.memberships.build(
        user: create(:user),
        role: :viewer
      )

      expect(extra_membership).not_to be_valid
      expect(extra_membership.errors[:base]).to include("Organization has reached the maximum of 1 seats on the Pro plan")
    end
  end
end
