require "rails_helper"

RSpec.describe AndroidBuild, type: :model do
  let(:user) { User.create!(email: "android-builds@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Android Org", owner: user) }
  let(:android_app) { AndroidApp.create!(organization: organization, package_name: "com.example.app", name: "Example App") }

  describe "validations" do
    it "requires a version_code" do
      build = described_class.new(organization: organization, android_app: android_app, version_code: nil)
      expect(build).not_to be_valid
      expect(build.errors[:version_code]).to include("can't be blank")
    end

    it "enforces unique version_code per app" do
      described_class.create!(organization: organization, android_app: android_app, version_code: "100")
      duplicate = described_class.new(organization: organization, android_app: android_app, version_code: "100")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:version_code]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let!(:older) { described_class.create!(organization: organization, android_app: android_app, version_code: "1", uploaded_at: 2.days.ago) }
    let!(:newer) { described_class.create!(organization: organization, android_app: android_app, version_code: "2", uploaded_at: 1.day.ago) }
    let!(:recent) { described_class.create!(organization: organization, android_app: android_app, version_code: "3", uploaded_at: Time.current) }

    it ".recent orders by uploaded_at/created_at descending" do
      expect(described_class.recent.pluck(:version_code)).to eq(%w[3 2 1])
    end

    it ".by_version filters by exact version_code" do
      expect(described_class.by_version("2")).to contain_exactly(newer)
    end

    it ".uploaded_after respects nil input" do
      expect(described_class.uploaded_after(nil).count).to eq(3)
    end

    it ".uploaded_after filters using uploaded_at fallback" do
      expect(described_class.uploaded_after(36.hours.ago)).to match_array([ newer, recent ])
    end
  end

  describe "#display_version" do
    it "combines version_name and version_code when both present" do
      build = described_class.new(version_name: "1.2.3", version_code: "123")
      expect(build.display_version).to eq("1.2.3 (123)")
    end

    it "falls back to version_code when version_name missing" do
      build = described_class.new(version_code: "200")
      expect(build.display_version).to eq("200")
    end
  end
end
