require "rails_helper"

RSpec.describe ScreenshotUpload, type: :model do
  let(:user) { User.create!(email: "uploads@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }
  let(:project) { ScreenshotProject.create!(organization: organization, name: "Test Project", platform: "both") }

  describe "validations" do
    it "is valid with valid attributes" do
      upload = described_class.new(
        screenshot_project: project,
        organization: organization,
        target: "app_store_connect"
      )
      expect(upload).to be_valid
    end

    it "requires a target" do
      upload = described_class.new(
        screenshot_project: project,
        organization: organization,
        target: ""
      )
      expect(upload).not_to be_valid
    end

    it "validates target inclusion" do
      upload = described_class.new(
        screenshot_project: project,
        organization: organization,
        target: "invalid"
      )
      expect(upload).not_to be_valid
    end

    %w[app_store_connect google_play].each do |target|
      it "accepts '#{target}' as a valid target" do
        upload = described_class.new(
          screenshot_project: project,
          organization: organization,
          target: target
        )
        expect(upload).to be_valid
      end
    end

    it "defaults status to pending" do
      upload = described_class.create!(
        screenshot_project: project,
        organization: organization,
        target: "app_store_connect"
      )
      expect(upload.status).to eq("pending")
    end
  end

  describe "associations" do
    it "belongs to a screenshot project" do
      upload = described_class.create!(
        screenshot_project: project,
        organization: organization,
        target: "google_play"
      )
      expect(upload.screenshot_project).to eq(project)
    end

    it "belongs to an organization" do
      upload = described_class.create!(
        screenshot_project: project,
        organization: organization,
        target: "google_play"
      )
      expect(upload.organization).to eq(organization)
    end
  end

  describe "status helpers" do
    let(:upload) do
      described_class.create!(
        screenshot_project: project,
        organization: organization,
        target: "app_store_connect"
      )
    end

    it "#pending? returns true for pending status" do
      expect(upload.pending?).to be true
    end

    it "#mark_in_progress! updates status and started_at" do
      upload.mark_in_progress!
      expect(upload.in_progress?).to be true
      expect(upload.started_at).to be_present
    end

    it "#mark_completed! updates status and completed_at" do
      upload.mark_completed!
      expect(upload.completed?).to be true
      expect(upload.completed_at).to be_present
    end

    it "#mark_failed! updates status and stores error" do
      upload.mark_failed!("Something went wrong")
      expect(upload.failed?).to be true
      expect(upload.progress["errors"]).to include("Something went wrong")
    end

    it "#update_progress! updates progress hash" do
      upload.update_progress!(completed: 5, total: 10, current_file: "screenshot_01.png")
      expect(upload.progress["completed"]).to eq(5)
      expect(upload.progress["total"]).to eq(10)
      expect(upload.progress["current_file"]).to eq("screenshot_01.png")
    end
  end

  describe "scopes" do
    it ".recent returns recent uploads ordered by created_at desc" do
      old = described_class.create!(screenshot_project: project, organization: organization, target: "app_store_connect", created_at: 2.days.ago)
      recent = described_class.create!(screenshot_project: project, organization: organization, target: "google_play")
      expect(described_class.recent.first).to eq(recent)
    end

    it ".by_status filters by status" do
      pending_upload = described_class.create!(screenshot_project: project, organization: organization, target: "app_store_connect")
      completed_upload = described_class.create!(screenshot_project: project, organization: organization, target: "google_play", status: "completed")

      expect(described_class.by_status("pending")).to include(pending_upload)
      expect(described_class.by_status("pending")).not_to include(completed_upload)
    end
  end
end
