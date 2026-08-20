module AppStoreConnect
  class BuildUploadStatusChecker
    BASE_URL = "https://api.appstoreconnect.apple.com"
    TERMINAL_APPLE_STATES = %w[COMPLETE FAILED INVALIDATED].freeze

    def initialize(credential:, build_upload:)
      @credential   = credential
      @build_upload = build_upload
    end

    def call
      return @build_upload if TERMINAL_APPLE_STATES.include?(@build_upload.apple_state)

      jwt = JwtMinter.for(@credential)
      conn = Faraday.new(BASE_URL) do |f|
        f.options.timeout      = 20
        f.options.open_timeout = 20
        f.adapter Faraday.default_adapter
      end
      resp = conn.get("/v1/buildUploads/#{@build_upload.remote_id}") { |r| r.headers["Authorization"] = "Bearer #{jwt}" }

      if resp.status.between?(200, 299)
        body = JSON.parse(resp.body)
        @build_upload.update!(
          apple_state:        body.dig("data", "attributes", "state", "state"),
          apple_state_detail: body.dig("data", "attributes", "state") || {}
        )
      end
      @build_upload
    end
  end
end
