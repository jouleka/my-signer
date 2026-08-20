require "rails_helper"

RSpec.describe AscBuildUpload do
  subject(:upload) { build(:asc_build_upload) }

  it "is valid with required attributes" do
    expect(upload).to be_valid
  end

  it "validates state inclusion" do
    upload.state = "bogus"
    expect(upload).not_to be_valid
    expect(upload.errors[:state]).to be_present
  end

  it "rejects a second pending row for the same app+version in the same org" do
    create(:asc_build_upload, organization: upload.organization, apple_app: upload.apple_app,
           cf_bundle_version: upload.cf_bundle_version, state: "pending")
    expect { upload.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows two uploaded rows for the same app+version" do
    create(:asc_build_upload, organization: upload.organization, apple_app: upload.apple_app,
           cf_bundle_version: upload.cf_bundle_version, state: "uploaded", uploaded_at: Time.current)
    upload.save!
    expect(upload).to be_persisted
  end

  describe "scopes" do
    let!(:pending)  { create(:asc_build_upload, state: "pending") }
    let!(:uploaded) { create(:asc_build_upload, state: "uploaded", uploaded_at: Time.current) }

    it ".pending returns only pending rows" do
      expect(described_class.pending).to contain_exactly(pending)
    end

    it ".uploaded returns only uploaded rows" do
      expect(described_class.uploaded).to contain_exactly(uploaded)
    end
  end
end
