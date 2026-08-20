require "rails_helper"

RSpec.describe Pricing::OrganizationOverageStatus, type: :service do
  describe "#any?" do
    it "returns false when usage is exactly at the current plan limit" do
      owner = create(:user, plan_tier: :free)
      organization = create(:organization, owner: owner)

      create(:screenshot_project, organization: organization)

      allow(ScreenshotProject).to receive(:org_media_storage_bytes).with(organization.id).and_return(organization.entitlements.max_media_storage_bytes_per_organization)
      allow(ScreenshotProject).to receive(:org_export_storage_bytes).with(organization.id).and_return(organization.entitlements.max_export_storage_bytes_per_organization)

      status = described_class.new(organization)

      expect(status).not_to be_any
      expect(status.sections).to be_empty
      expect(status.seats_overage).to eq(0)
      expect(status.screenshot_projects_overage).to eq(0)
      expect(status.media_storage_overage).to eq(0)
      expect(status.export_storage_overage).to eq(0)
    end
  end

  describe "#sections" do
    it "reports overages and overflowing screenshot projects oldest-first" do
      owner = create(:user, :team_plan)
      organization = create(:organization, owner: owner)
      teammate = create(:user, email: "teammate@example.com")

      create(:screenshot_project, organization: organization, name: "Project 1", created_at: 3.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 2", created_at: 2.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 3", created_at: 1.day.ago)
      organization.memberships.create!(user: teammate, role: :developer)
      organization.organization_invitations.create!(inviter: owner, email: "pending@example.com", role: :viewer)

      owner.update!(plan_tier: :free)
      allow(ScreenshotProject).to receive(:org_media_storage_bytes).with(organization.id).and_return(301.megabytes)
      allow(ScreenshotProject).to receive(:org_export_storage_bytes).with(organization.id).and_return(501.megabytes)

      status = described_class.new(organization)

      expect(status).to be_any
      expect(status.seats_overage).to eq(2)
      expect(status.screenshot_projects_overage).to eq(2)
      expect(status.media_storage_overage).to eq(1.megabyte)
      expect(status.export_storage_overage).to eq(1.megabyte)
      expect(status.overflow_screenshot_projects.map(&:name)).to eq([ "Project 2", "Project 3" ])
      expect(status.project_overflow?(organization.screenshot_projects.find_by!(name: "Project 2"))).to be(true)
      expect(status.project_overflow?(organization.screenshot_projects.find_by!(name: "Project 1"))).to be(false)
      expect(status.sections.map { |section| section[:key] }).to include(
        :seats,
        :screenshot_projects,
        :media_storage_bytes,
        :export_storage_bytes
      )
    end

    it "can forecast overages against a lower target tier without changing the active plan" do
      owner = create(:user, :team_plan)
      organization = create(:organization, owner: owner)
      teammate_one = create(:user, email: "forecast-one@example.com")
      teammate_two = create(:user, email: "forecast-two@example.com")

      create(:screenshot_project, organization: organization, name: "Project 1", created_at: 10.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 2", created_at: 9.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 3", created_at: 8.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 4", created_at: 7.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 5", created_at: 6.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 6", created_at: 5.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 7", created_at: 4.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 8", created_at: 3.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 9", created_at: 2.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 10", created_at: 1.day.ago)
      create(:screenshot_project, organization: organization, name: "Project 11", created_at: 12.hours.ago)
      create(:screenshot_project, organization: organization, name: "Project 12", created_at: 6.hours.ago)
      organization.memberships.create!(user: teammate_one, role: :developer)
      organization.memberships.create!(user: teammate_two, role: :developer)
      organization.organization_invitations.create!(inviter: owner, email: "forecast-pending@example.com", role: :viewer)

      allow(ScreenshotProject).to receive(:org_media_storage_bytes).with(organization.id).and_return(3.gigabytes)
      allow(ScreenshotProject).to receive(:org_export_storage_bytes).with(organization.id).and_return(6.gigabytes)

      status = described_class.new(organization, tier: :pro)

      expect(status).to be_any
      expect(status.seats_overage).to eq(3)
      expect(status.screenshot_projects_overage).to eq(2)
      expect(status.media_storage_overage).to eq(1.gigabyte)
      expect(status.export_storage_overage).to eq(1.gigabyte)
      expect(status.overflow_screenshot_projects.map(&:name)).to eq([ "Project 11", "Project 12" ])
    end
  end
end
