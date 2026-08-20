require "rails_helper"

RSpec.describe AppStoreConnect::Reviews do
  let(:client) { instance_double(AppStoreConnect::Client) }
  let(:reviews_service) { described_class.new(client) }

  describe "#list" do
    it "paginates through customer reviews" do
      page_data = {
        "data" => [
          { "id" => "r1", "attributes" => { "rating" => 5, "body" => "Great!" } },
          { "id" => "r2", "attributes" => { "rating" => 2, "body" => "Bad." } }
        ],
        "links" => {}
      }

      expect(client).to receive(:paginate)
        .with("apps/app123/customerReviews", params: { "limit" => 200, "sort" => "-createdDate" })
        .and_yield(page_data)

      pages = []
      reviews_service.list(app_id: "app123") { |p| pages << p }
      expect(pages.size).to eq(1)
      expect(pages.first["data"].size).to eq(2)
    end

    it "caps limit at 200" do
      expect(client).to receive(:paginate)
        .with("apps/app123/customerReviews", params: { "limit" => 200, "sort" => "-createdDate" })

      reviews_service.list(app_id: "app123", limit: 500)
    end
  end

  describe "#post_response" do
    it "posts a developer response" do
      expected_json = {
        data: {
          type: "customerReviewResponses",
          attributes: { responseBody: "Thanks!" },
          relationships: {
            review: { data: { type: "customerReviews", id: "r1" } }
          }
        }
      }

      expect(client).to receive(:post)
        .with("customerReviewResponses", json: expected_json)
        .and_return({ "data" => { "id" => "resp1" } })

      result = reviews_service.post_response(review_id: "r1", response_body: "Thanks!")
      expect(result).to be_a(Hash)
    end
  end

  describe "#delete_response" do
    it "deletes a developer response" do
      expect(client).to receive(:delete)
        .with("customerReviewResponses/resp1")
        .and_return({})

      reviews_service.delete_response(response_id: "resp1")
    end
  end
end
