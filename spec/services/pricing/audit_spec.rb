require "rails_helper"

RSpec.describe Pricing::PlanTransitionAudit do
  describe "#to_h" do
    it "reports blocked organizations and all downgrade violations for a free-plan transition" do
      owner = create(:user, :team_plan)
      kept_organization = create(:organization, owner: owner, name: "Kept Org", created_at: 2.days.ago)
      create(:organization, owner: owner, name: "Blocked Org", created_at: 1.day.ago)
      teammate = create(:user, email: "teammate@example.com")

      kept_organization.memberships.create!(user: teammate, role: :developer)
      create(:screenshot_project, organization: kept_organization, name: "Project 1")
      create(:screenshot_project, organization: kept_organization, name: "Project 2")

      allow(ScreenshotProject).to receive(:org_media_storage_bytes).and_call_original
      allow(ScreenshotProject).to receive(:org_export_storage_bytes).and_call_original
      allow(ScreenshotProject).to receive(:org_media_storage_bytes).with(kept_organization.id).and_return(301.megabytes)
      allow(ScreenshotProject).to receive(:org_export_storage_bytes).with(kept_organization.id).and_return(501.megabytes)

      report = described_class.new(user: owner, target_tier: :free).to_h

      expect(report[:blocked_organizations].map(&:name)).to eq([ "Blocked Org" ])
      expect(report[:organization_violations].map { |entry| entry[:type] }).to include(
        :seats,
        :screenshot_projects,
        :media_storage_bytes,
        :export_storage_bytes
      )

      warning_messages = described_class.new(user: owner, target_tier: :free).warning_messages.join(" ")
      expect(warning_messages).to include("Blocked Org")
      expect(warning_messages).to include("Kept Org exceeds the seat limit")
    end
  end
end
