module GooglePlay
  class Reviews
    def initialize(client)
      @client = client
    end

    # Lists reviews for a given package. Google Play reviews API does NOT
    # require an edit session (unlike listings).
    # Returns the raw response from the Google API.
    def list(package_name:, translation_language: nil)
      opts = {}
      opts[:translation_language] = translation_language if translation_language
      @client.service.list_reviews(package_name, **opts)
    end

    # Replies to a review. Google Play limits reply text to 350 characters.
    # Returns the reply result from the Google API.
    def reply(package_name:, review_id:, reply_text:)
      request_body = Google::Apis::AndroidpublisherV3::ReviewsReplyRequest.new(
        reply_text: reply_text
      )
      @client.service.reply_review(package_name, review_id, request_body)
    end
  end
end
