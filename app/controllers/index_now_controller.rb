# frozen_string_literal: true

# IndexNow integration for instant indexing on Bing, Yandex, Naver, Seznam.
# When content changes, call IndexNowController.notify(urls) to ping search engines.
# See: https://www.indexnow.org/documentation
class IndexNowController < ActionController::Base
  API_KEY = Rails.application.credentials.dig(:index_now, :api_key).presence || "496358d2fd7fabfb416ed2eafa4e87d8"
  HOST = "https://mysigner.dev"
  KEY_LOCATION = "#{HOST}/#{API_KEY}.txt"

  # GET /:key.txt — verification endpoint for IndexNow
  def verify
    if params[:key] == API_KEY
      render plain: API_KEY, content_type: "text/plain"
    else
      head :not_found
    end
  end

  # Notify IndexNow-supporting engines about URL changes.
  # Usage: IndexNowController.notify(["/docs/commands/ship", "/docs/guides/ci-cd-github"])
  def self.notify(paths)
    return unless Rails.env.production?

    urls = paths.map { |p| "#{HOST}#{p}" }

    payload = {
      host: "mysigner.dev",
      key: API_KEY,
      keyLocation: KEY_LOCATION,
      urlList: urls
    }

    # Submit to IndexNow API (Bing endpoint, which shares with other engines)
    uri = URI("https://api.indexnow.org/indexnow")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json; charset=utf-8")
    request.body = payload.to_json

    begin
      http.request(request)
    rescue StandardError => e
      Rails.logger.warn("IndexNow notification failed: #{e.message}")
    end
  end
end
