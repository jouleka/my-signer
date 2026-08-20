require "rails_helper"

RSpec.describe ScreenshotExport, type: :model do
  let(:user) { User.create!(email: "exports@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }
  let(:project) { ScreenshotProject.create!(organization: organization, name: "Export Test", platform: "both") }

  describe "validations" do
    it "is valid with valid attributes" do
      export = described_class.new(
        screenshot_project: project,
        resolution: "1320x2868",
        scene_position: 1,
        export_format: "standard"
      )
      expect(export).to be_valid
    end

    it "requires resolution" do
      export = described_class.new(screenshot_project: project, resolution: nil, scene_position: 1, export_format: "standard")
      expect(export).not_to be_valid
      expect(export.errors[:resolution]).to include("can't be blank")
    end

    it "requires scene_position" do
      export = described_class.new(screenshot_project: project, resolution: "1320x2868", scene_position: nil, export_format: "standard")
      expect(export).not_to be_valid
      expect(export.errors[:scene_position]).to include("can't be blank")
    end

    it "validates export_format inclusion" do
      export = described_class.new(screenshot_project: project, resolution: "1320x2868", scene_position: 1, export_format: "invalid")
      expect(export).not_to be_valid
      expect(export.errors[:export_format]).to include("is not included in the list")
    end

    %w[standard fastlane].each do |format|
      it "accepts '#{format}' as a valid export_format" do
        export = described_class.new(screenshot_project: project, resolution: "1320x2868", scene_position: 1, export_format: format)
        expect(export).to be_valid
      end
    end
  end

  describe "associations" do
    it "belongs to a screenshot_project" do
      export = described_class.create!(screenshot_project: project, resolution: "1320x2868", scene_position: 1, export_format: "standard")
      expect(export.screenshot_project).to eq(project)
    end

    it "is destroyed when the parent project is destroyed" do
      described_class.create!(screenshot_project: project, resolution: "1320x2868", scene_position: 1, export_format: "standard")
      expect { project.destroy }.to change(described_class, :count).by(-1)
    end
  end

  describe "scopes" do
    before do
      described_class.create!(screenshot_project: project, resolution: "1320x2868", scene_position: 1, export_format: "standard", locale: "en-US")
      described_class.create!(screenshot_project: project, resolution: "1080x1920", scene_position: 2, export_format: "fastlane", locale: "de-DE")
      described_class.create!(screenshot_project: project, resolution: "1320x2868", scene_position: 3, export_format: "standard", locale: "")
    end

    describe ".for_resolution" do
      it "filters by resolution" do
        results = described_class.for_resolution("1320x2868")
        expect(results.count).to eq(2)
        expect(results.pluck(:resolution).uniq).to eq([ "1320x2868" ])
      end
    end

    describe ".for_locale" do
      it "filters by locale" do
        results = described_class.for_locale("en-US")
        expect(results.count).to eq(1)
        expect(results.first.locale).to eq("en-US")
      end

      it "filters by empty string when locale is blank" do
        results = described_class.for_locale("")
        expect(results.count).to eq(1)
        expect(results.first.locale).to eq("")
      end

      it "filters by empty string when locale is nil" do
        results = described_class.for_locale(nil)
        expect(results.count).to eq(1)
        expect(results.first.locale).to eq("")
      end
    end

    describe ".fastlane" do
      it "returns only fastlane exports" do
        results = described_class.fastlane
        expect(results.count).to eq(1)
        expect(results.first.export_format).to eq("fastlane")
      end
    end

    describe ".standard" do
      it "returns only standard exports" do
        results = described_class.standard
        expect(results.count).to eq(2)
        expect(results.pluck(:export_format).uniq).to eq([ "standard" ])
      end
    end
  end

  describe ".upsert_export!" do
    let(:image_data) { "\x89PNG\r\n\x1A\n".b + ("pixel_data" * 10).b }

    it "creates a new export record with an attached image" do
      expect {
        record = described_class.upsert_export!(
          project: project,
          resolution: "1320x2868",
          scene_position: 1,
          image_data: image_data
        )
        expect(record).to be_persisted
        expect(record.resolution).to eq("1320x2868")
        expect(record.scene_position).to eq(1)
        expect(record.export_format).to eq("standard")
        expect(record.locale).to eq("")
        expect(record.image).to be_attached
      }.to change(described_class, :count).by(1)
    end

    it "overwrites an existing record with the same key (deduplication)" do
      described_class.upsert_export!(
        project: project,
        resolution: "1320x2868",
        scene_position: 1,
        image_data: image_data
      )

      new_image_data = "\x89PNG\r\n\x1A\n".b + ("new_pixels" * 20).b

      expect {
        record = described_class.upsert_export!(
          project: project,
          resolution: "1320x2868",
          scene_position: 1,
          image_data: new_image_data
        )
        expect(record).to be_persisted
        expect(record.image).to be_attached
      }.not_to change(described_class, :count)
    end

    it "creates separate records for different locales" do
      expect {
        described_class.upsert_export!(project: project, resolution: "1320x2868", scene_position: 1, locale: "en-US", image_data: image_data)
        described_class.upsert_export!(project: project, resolution: "1320x2868", scene_position: 1, locale: "de-DE", image_data: image_data)
      }.to change(described_class, :count).by(2)
    end

    it "creates separate records for different scene positions" do
      expect {
        described_class.upsert_export!(project: project, resolution: "1320x2868", scene_position: 1, image_data: image_data)
        described_class.upsert_export!(project: project, resolution: "1320x2868", scene_position: 2, image_data: image_data)
      }.to change(described_class, :count).by(2)
    end

    it "stores fastlane export_format when specified" do
      record = described_class.upsert_export!(
        project: project,
        resolution: "1320x2868",
        scene_position: 1,
        image_data: image_data,
        export_format: "fastlane"
      )
      expect(record.export_format).to eq("fastlane")
    end

    it "normalizes nil locale to empty string" do
      record = described_class.upsert_export!(
        project: project,
        resolution: "1320x2868",
        scene_position: 1,
        locale: nil,
        image_data: image_data
      )
      expect(record.locale).to eq("")
    end

    it "generates a zero-padded filename" do
      record = described_class.upsert_export!(
        project: project,
        resolution: "1320x2868",
        scene_position: 3,
        image_data: image_data
      )
      expect(record.image.blob.filename.to_s).to eq("screenshot_03.png")
    end
  end

  describe ".org_cloud_export_storage_bytes" do
    it "returns 0 when no cloud exports exist" do
      bytes = described_class.org_cloud_export_storage_bytes(organization.id)
      expect(bytes).to eq(0)
    end

    it "sums byte sizes across all exports for the organization" do
      image_data_1 = "\x89PNG\r\n\x1A\n".b + ("a" * 100).b
      image_data_2 = "\x89PNG\r\n\x1A\n".b + ("b" * 200).b

      described_class.upsert_export!(project: project, resolution: "1320x2868", scene_position: 1, image_data: image_data_1)
      described_class.upsert_export!(project: project, resolution: "1320x2868", scene_position: 2, image_data: image_data_2)

      bytes = described_class.org_cloud_export_storage_bytes(organization.id)
      expect(bytes).to eq(image_data_1.bytesize + image_data_2.bytesize)
    end

    it "does not include exports from other organizations" do
      other_user = User.create!(email: "other-export@example.com", password: "SecurePass123!", confirmed_at: Time.current)
      other_org = Organization.create!(name: "Other Org", owner: other_user)
      other_project = ScreenshotProject.create!(organization: other_org, name: "Other", platform: "both")

      image_data = "\x89PNG\r\n\x1A\n".b + ("x" * 100).b
      described_class.upsert_export!(project: project, resolution: "1320x2868", scene_position: 1, image_data: image_data)
      described_class.upsert_export!(project: other_project, resolution: "1320x2868", scene_position: 1, image_data: image_data)

      bytes = described_class.org_cloud_export_storage_bytes(organization.id)
      expect(bytes).to eq(image_data.bytesize)
    end
  end
end
