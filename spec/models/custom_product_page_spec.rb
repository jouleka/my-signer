require "rails_helper"

RSpec.describe CustomProductPage, type: :model do
  let(:organization) { create(:organization) }
  let(:apple_app) { create(:apple_app, organization: organization) }

  describe "associations" do
    it "belongs to organization" do
      cpp = create(:custom_product_page, organization: organization, apple_app: apple_app)
      expect(cpp.organization).to eq(organization)
    end

    it "belongs to apple_app" do
      cpp = create(:custom_product_page, organization: organization, apple_app: apple_app)
      expect(cpp.apple_app).to eq(apple_app)
    end

    it "has many versions" do
      cpp = create(:custom_product_page, organization: organization, apple_app: apple_app)
      version = create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      expect(cpp.custom_product_page_versions).to include(version)
    end

    it "destroys versions when destroyed" do
      cpp = create(:custom_product_page, organization: organization, apple_app: apple_app)
      create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      expect { cpp.destroy }.to change(CustomProductPageVersion, :count).by(-1)
    end

    it "has many localizations through versions" do
      cpp = create(:custom_product_page, organization: organization, apple_app: apple_app)
      version = create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
      loc = create(:custom_product_page_localization, custom_product_page_version: version, organization: organization)
      expect(cpp.custom_product_page_localizations).to include(loc)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      cpp = build(:custom_product_page, organization: organization, apple_app: apple_app)
      expect(cpp).to be_valid
    end

    it "requires remote_id" do
      cpp = build(:custom_product_page, remote_id: nil)
      expect(cpp).not_to be_valid
      expect(cpp.errors[:remote_id]).to include("can't be blank")
    end

    it "requires unique remote_id" do
      create(:custom_product_page, organization: organization, apple_app: apple_app, remote_id: "unique_id")
      duplicate = build(:custom_product_page, organization: organization, apple_app: apple_app, remote_id: "unique_id")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:remote_id]).to include("has already been taken")
    end

    it "requires name" do
      cpp = build(:custom_product_page, name: nil)
      expect(cpp).not_to be_valid
      expect(cpp.errors[:name]).to include("can't be blank")
    end
  end

  describe "scopes" do
    describe ".visible" do
      it "returns only visible CPPs" do
        visible_cpp = create(:custom_product_page, organization: organization, apple_app: apple_app, visible: true)
        create(:custom_product_page, organization: organization, apple_app: apple_app, visible: false)

        expect(CustomProductPage.visible).to eq([ visible_cpp ])
      end
    end

    describe ".for_app" do
      it "returns CPPs for a specific app" do
        cpp = create(:custom_product_page, organization: organization, apple_app: apple_app)
        other_org = create(:organization)
        other_app = create(:apple_app, organization: other_org)
        create(:custom_product_page, organization: other_org, apple_app: other_app)

        expect(CustomProductPage.for_app(apple_app)).to eq([ cpp ])
      end
    end

    describe ".ordered" do
      it "returns CPPs ordered by created_at desc" do
        old_cpp = create(:custom_product_page, organization: organization, apple_app: apple_app, created_at: 2.days.ago)
        new_cpp = create(:custom_product_page, organization: organization, apple_app: apple_app, created_at: 1.day.ago)

        expect(CustomProductPage.ordered).to eq([ new_cpp, old_cpp ])
      end
    end
  end

  describe "version helpers" do
    let(:cpp) { create(:custom_product_page, organization: organization, apple_app: apple_app) }

    describe "#published_version" do
      it "returns the published version" do
        published = create(:custom_product_page_version, :published, custom_product_page: cpp, organization: organization)
        create(:custom_product_page_version, custom_product_page: cpp, organization: organization)

        expect(cpp.published_version).to eq(published)
      end

      it "returns nil when no published version exists" do
        create(:custom_product_page_version, custom_product_page: cpp, organization: organization)
        expect(cpp.published_version).to be_nil
      end
    end

    describe "#draft_version" do
      it "returns the draft version" do
        draft = create(:custom_product_page_version, custom_product_page: cpp, organization: organization, state: "PREPARE_FOR_SUBMISSION")
        expect(cpp.draft_version).to eq(draft)
      end
    end

    describe "#latest_version" do
      it "returns the most recent version" do
        create(:custom_product_page_version, custom_product_page: cpp, organization: organization, created_at: 2.days.ago)
        latest = create(:custom_product_page_version, custom_product_page: cpp, organization: organization, created_at: 1.day.ago)

        expect(cpp.latest_version).to eq(latest)
      end
    end
  end

  describe "performance methods" do
    let(:cpp) { build(:custom_product_page, organization: organization, apple_app: apple_app, performance_data: { "impressions" => 1000, "downloads" => 150, "conversion_rate" => 0.15 }) }

    it "returns performance_impressions" do
      expect(cpp.performance_impressions).to eq(1000)
    end

    it "returns performance_downloads" do
      expect(cpp.performance_downloads).to eq(150)
    end

    it "returns performance_conversion_rate" do
      expect(cpp.performance_conversion_rate).to eq(0.15)
    end

    it "returns performance_available? true when data present" do
      expect(cpp.performance_available?).to be true
    end

    it "returns performance_available? false when data empty" do
      cpp.performance_data = {}
      expect(cpp.performance_available?).to be false
    end
  end
end
