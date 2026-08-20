require "rails_helper"

RSpec.describe GooglePlay::Reviews do
  let(:mock_service) { instance_double(Google::Apis::AndroidpublisherV3::AndroidPublisherService) }
  let(:mock_client) { instance_double(GooglePlay::Client, service: mock_service) }
  let(:subject) { described_class.new(mock_client) }

  describe "#list" do
    it "passes translation_language when provided" do
      expect(mock_service).to receive(:list_reviews)
        .with("com.example.app", translation_language: "en")
        .and_return(double(reviews: []))
      subject.list(package_name: "com.example.app", translation_language: "en")
    end

    it "does not pass translation_language when nil" do
      expect(mock_service).to receive(:list_reviews)
        .with("com.example.app")
        .and_return(double(reviews: []))
      subject.list(package_name: "com.example.app")
    end
  end
end
