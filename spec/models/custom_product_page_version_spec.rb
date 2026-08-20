require "rails_helper"

RSpec.describe CustomProductPageVersion, type: :model do
  let(:organization) { create(:organization) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }

  describe "associations" do
    it "belongs to custom_product_page" do
      version = create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      expect(version.custom_product_page).to eq(cpp)
    end

    it "belongs to organization" do
      version = create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      expect(version.organization).to eq(organization)
    end

    it "has many localizations" do
      version = create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      loc = create(:custom_product_page_localization, custom_product_page_version: version, organization: organization)
      expect(version.custom_product_page_localizations).to include(loc)
    end

    it "destroys localizations when destroyed" do
      version = create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      create(:custom_product_page_localization, custom_product_page_version: version, organization: organization)
      expect { version.destroy }.to change(CustomProductPageLocalization, :count).by(-1)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      version = build(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      expect(version).to be_valid
    end

    it "requires remote_id" do
      version = build(:custom_product_page_version, remote_id: nil)
      expect(version).not_to be_valid
      expect(version.errors[:remote_id]).to include("can't be blank")
    end

    it "requires unique remote_id" do
      create(:custom_product_page_version, custom_product_page: cpp, organization: organization, remote_id: "ver_unique")
      duplicate = build(:custom_product_page_version, custom_product_page: cpp, organization: organization, remote_id: "ver_unique")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:remote_id]).to include("has already been taken")
    end

    it "requires state" do
      version = build(:custom_product_page_version, state: nil)
      expect(version).not_to be_valid
      expect(version.errors[:state]).to include("can't be blank")
    end

    it "validates state inclusion" do
      version = build(:custom_product_page_version, state: "INVALID")
      expect(version).not_to be_valid
      expect(version.errors[:state]).to be_present
    end

    it "accepts PREPARE_FOR_SUBMISSION state" do
      version = build(:custom_product_page_version, custom_product_page: cpp, organization: organization, state: "PREPARE_FOR_SUBMISSION")
      expect(version).to be_valid
    end

    it "accepts PUBLISHED state" do
      version = build(:custom_product_page_version, custom_product_page: cpp, organization: organization, state: "PUBLISHED")
      expect(version).to be_valid
    end
  end

  describe "#draft?" do
    it "returns true for PREPARE_FOR_SUBMISSION" do
      version = build(:custom_product_page_version, state: "PREPARE_FOR_SUBMISSION")
      expect(version.draft?).to be true
    end

    it "returns false for PUBLISHED" do
      version = build(:custom_product_page_version, state: "PUBLISHED")
      expect(version.draft?).to be false
    end
  end

  describe "#published?" do
    it "returns true for PUBLISHED" do
      version = build(:custom_product_page_version, state: "PUBLISHED")
      expect(version.published?).to be true
    end

    it "returns false for PREPARE_FOR_SUBMISSION" do
      version = build(:custom_product_page_version, state: "PREPARE_FOR_SUBMISSION")
      expect(version.published?).to be false
    end
  end
end
