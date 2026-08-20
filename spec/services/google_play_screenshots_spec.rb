require "rails_helper"

RSpec.describe GooglePlay::Screenshots do
  let(:mock_client) { instance_double(GooglePlay::Client) }
  let(:mock_service) { instance_double(Google::Apis::AndroidpublisherV3::AndroidPublisherService) }
  let(:screenshots) { described_class.new(mock_client) }

  before do
    allow(mock_client).to receive(:service).and_return(mock_service)
  end

  describe "IMAGE_TYPES" do
    it "maps phone resolution" do
      expect(described_class::IMAGE_TYPES["1080x1920"]).to eq("phoneScreenshots")
    end

    it "maps 7\" tablet resolution" do
      expect(described_class::IMAGE_TYPES["1200x1920"]).to eq("sevenInchScreenshots")
    end

    it "maps 10\" tablet resolution" do
      expect(described_class::IMAGE_TYPES["1600x2560"]).to eq("tenInchScreenshots")
    end
  end

  describe "#image_type_for_resolution" do
    it "returns image type for known resolution" do
      expect(screenshots.image_type_for_resolution(1080, 1920)).to eq("phoneScreenshots")
    end

    it "returns nil for unknown resolution" do
      expect(screenshots.image_type_for_resolution(999, 999)).to be_nil
    end
  end

  describe "#upload_image!" do
    let(:edit) { double("edit", id: "edit-123") }

    it "creates edit, uploads, and commits" do
      expect(mock_client).to receive(:create_edit).with("com.example.app").and_return(edit)
      expect(mock_service).to receive(:upload_edit_image)
        .with("com.example.app", "edit-123", "en-US", "phoneScreenshots", upload_source: "/path/to/screenshot.png", content_type: "image/png")
      expect(mock_client).to receive(:commit_edit).with("com.example.app", "edit-123")

      screenshots.upload_image!(
        package_name: "com.example.app",
        language: "en-US",
        image_type: "phoneScreenshots",
        file_path: "/path/to/screenshot.png"
      )
    end

    it "deletes edit on failure" do
      expect(mock_client).to receive(:create_edit).with("com.example.app").and_return(edit)
      expect(mock_service).to receive(:upload_edit_image).and_raise(StandardError, "upload failed")
      expect(mock_client).to receive(:delete_edit).with("com.example.app", "edit-123")

      expect {
        screenshots.upload_image!(
          package_name: "com.example.app",
          language: "en-US",
          image_type: "phoneScreenshots",
          file_path: "/path/to/screenshot.png"
        )
      }.to raise_error(StandardError, "upload failed")
    end
  end

  describe "#delete_all_images" do
    let(:edit) { double("edit", id: "edit-456") }

    it "creates edit, deletes all, and commits" do
      expect(mock_client).to receive(:create_edit).with("com.example.app").and_return(edit)
      expect(mock_service).to receive(:deleteall_edit_image)
        .with("com.example.app", "edit-456", "en-US", "phoneScreenshots")
      expect(mock_client).to receive(:commit_edit).with("com.example.app", "edit-456")

      screenshots.delete_all_images(
        package_name: "com.example.app",
        language: "en-US",
        image_type: "phoneScreenshots"
      )
    end
  end

  describe "#list_images" do
    it "lists images" do
      response = double("response", images: [ double("image", id: "img-1") ])
      expect(mock_service).to receive(:list_edit_images)
        .with("com.example.app", "edit-1", "en-US", "phoneScreenshots")
        .and_return(response)

      result = screenshots.list_images(
        package_name: "com.example.app",
        edit_id: "edit-1",
        language: "en-US",
        image_type: "phoneScreenshots"
      )
      expect(result.length).to eq(1)
    end
  end
end
