module AppStoreConnect
  class Reviews
    def initialize(client)
      @client = client
    end

    # Paginates through all customer reviews for an app.
    # Yields each page body so the caller can process reviews in batches.
    def list(app_id:, limit: 200, &block)
      @client.paginate(
        "apps/#{app_id}/customerReviews",
        params: { "limit" => [ limit, 200 ].min, "sort" => "-createdDate" },
        &block
      )
    end

    # Posts a developer response to a customer review.
    # Apple returns 201 on success.
    def post_response(review_id:, response_body:)
      @client.post("customerReviewResponses", json: {
        data: {
          type: "customerReviewResponses",
          attributes: {
            responseBody: response_body
          },
          relationships: {
            review: {
              data: { type: "customerReviews", id: review_id }
            }
          }
        }
      })
    end

    # Deletes a developer response. Apple returns 204 on success.
    def delete_response(response_id:)
      @client.delete("customerReviewResponses/#{response_id}")
    end
  end
end
