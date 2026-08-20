require "rails_helper"

RSpec.describe CustomProductPageLocalization, type: :model do
  let(:organization) { create(:organization) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }
  let(:version) { create(:custom_product_page_version, custom_product_page: cpp, organization: organization) }

  describe "associations" do
    it "belongs to custom_product_page_version" do
      loc = create(:custom_product_page_localization, custom_product_page_version: version, organization: organization)
      expect(loc.custom_product_page_version).to eq(version)
    end

    it "belongs to organization" do
      loc = create(:custom_product_page_localization, custom_product_page_version: version, organization: organization)
      expect(loc.organization).to eq(organization)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      loc = build(:custom_product_page_localization, custom_product_page_version: version, organization: organization)
      expect(loc).to be_valid
    end

    it "requires remote_id" do
      loc = build(:custom_product_page_localization, remote_id: nil)
      expect(loc).not_to be_valid
      expect(loc.errors[:remote_id]).to include("can't be blank")
    end

    it "requires unique remote_id" do
      create(:custom_product_page_localization, custom_product_page_version: version, organization: organization, remote_id: "loc_unique")
      duplicate = build(:custom_product_page_localization, custom_product_page_version: version, organization: organization, remote_id: "loc_unique")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:remote_id]).to include("has already been taken")
    end

    it "requires locale" do
      loc = build(:custom_product_page_localization, locale: nil)
      expect(loc).not_to be_valid
      expect(loc.errors[:locale]).to include("can't be blank")
    end

    it "requires unique locale per version" do
      create(:custom_product_page_localization, custom_product_page_version: version, organization: organization, locale: "en-US")
      duplicate = build(:custom_product_page_localization, custom_product_page_version: version, organization: organization, locale: "en-US")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:locale]).to include("has already been taken")
    end

    it "allows same locale on different versions" do
      version2 = create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      create(:custom_product_page_localization, custom_product_page_version: version, organization: organization, locale: "en-US")
      loc2 = build(:custom_product_page_localization, custom_product_page_version: version2, organization: organization, locale: "en-US")
      expect(loc2).to be_valid
    end
  end
end
