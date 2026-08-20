require "rails_helper"

RSpec.describe SyncChangeDetector do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }

  subject(:detector) { described_class.new(organization) }

  describe "#snapshot_before and #detect_changes" do
    it "detects newly added certificates" do
      detector.snapshot_before

      create(:apple_certificate, organization: organization)

      changes = detector.detect_changes
      expect(changes).to include(a_string_matching(/1 new apple certificate/))
    end

    it "detects multiple new resources" do
      detector.snapshot_before

      create(:apple_certificate, organization: organization)
      create(:apple_certificate, organization: organization)

      changes = detector.detect_changes
      expect(changes).to include(a_string_matching(/2 new apple certificates/))
    end

    it "detects removed resources" do
      cert = create(:apple_certificate, organization: organization)
      detector.snapshot_before

      cert.destroy!

      changes = detector.detect_changes
      expect(changes).to include(a_string_matching(/1 apple certificate removed/))
    end

    it "returns empty when no changes" do
      create(:apple_certificate, organization: organization)
      detector.snapshot_before

      changes = detector.detect_changes
      expect(changes).to be_empty
    end
  end

  describe "#changes?" do
    it "returns false before detect_changes is called" do
      expect(detector.changes?).to be false
    end

    it "returns true when changes are detected" do
      detector.snapshot_before
      create(:apple_certificate, organization: organization)
      detector.detect_changes
      expect(detector.changes?).to be true
    end

    it "returns false when no changes are detected" do
      detector.snapshot_before
      detector.detect_changes
      expect(detector.changes?).to be false
    end
  end

  describe "#total_changes" do
    it "returns 0 when no snapshot was taken" do
      expect(detector.total_changes).to eq(0)
    end

    it "returns absolute sum of net changes" do
      detector.snapshot_before

      create(:apple_certificate, organization: organization)
      create(:apple_provisioning_profile, organization: organization)

      expect(detector.total_changes).to eq(2)
    end

    it "returns zero when additions and removals cancel out" do
      cert = create(:apple_certificate, organization: organization)
      detector.snapshot_before

      cert.destroy!
      create(:apple_provisioning_profile, organization: organization)

      # Net change is 0 (one removed, one added in different categories — sum of diffs)
      expect(detector.total_changes).to eq(0)
    end
  end
end
