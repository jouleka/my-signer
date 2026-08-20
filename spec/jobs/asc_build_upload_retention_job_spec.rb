require "rails_helper"

RSpec.describe AscBuildUploadRetentionJob do
  describe "#perform" do
    it "deletes terminal rows older than 90 days" do
      old_uploaded = create(:asc_build_upload, state: "uploaded", uploaded_at: 100.days.ago, created_at: 100.days.ago)
      recent       = create(:asc_build_upload, state: "uploaded", uploaded_at: 10.days.ago,  created_at: 10.days.ago)

      described_class.new.perform

      expect(AscBuildUpload.exists?(old_uploaded.id)).to be(false)
      expect(AscBuildUpload.exists?(recent.id)).to be(true)
    end

    it "marks pending rows older than 24h as abandoned" do
      orphan = create(:asc_build_upload, state: "pending", created_at: 25.hours.ago)
      fresh  = create(:asc_build_upload, state: "pending", created_at: 1.hour.ago)

      described_class.new.perform

      expect(orphan.reload.state).to eq("abandoned")
      expect(fresh.reload.state).to eq("pending")
    end
  end
end
