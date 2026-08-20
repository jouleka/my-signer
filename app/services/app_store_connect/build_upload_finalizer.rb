module AppStoreConnect
  class BuildUploadFinalizer
    class Error < StandardError; end
    class AppleError < Error; end

    BASE_URL = "https://api.appstoreconnect.apple.com"

    def initialize(credential:, build_upload:, checksums:)
      @credential   = credential
      @build_upload = build_upload
      @checksums    = checksums
    end

    def call
      jwt = JwtMinter.for(@credential)

      patch_resp = patch_file!(jwt)
      unless patch_resp.status.between?(200, 299) || patch_resp.status == 409
        raise AppleError, "PATCH /buildUploadFiles returned #{patch_resp.status}: #{patch_resp.body}"
      end

      upload_state = fetch_upload_state!(jwt)

      @build_upload.update!(
        state:               "uploaded",
        apple_state:         upload_state.dig("data", "attributes", "state", "state"),
        apple_state_detail:  upload_state.dig("data", "attributes", "state") || {},
        uploaded_at:         Time.current
      )
      @build_upload
    end

    private

    def patch_file!(jwt)
      conn.patch("/v1/buildUploadFiles/#{@build_upload.remote_file_id}") do |req|
        req.headers["Authorization"] = "Bearer #{jwt}"
        req.headers["Content-Type"]  = "application/json"
        req.body = {
          data: {
            type: "buildUploadFiles",
            id:   @build_upload.remote_file_id,
            attributes: {
              uploaded: true,
              sourceFileChecksums: { md5: @checksums[:md5], sha256: @checksums[:sha256] }.compact
            }
          }
        }.to_json
      end
    end

    def fetch_upload_state!(jwt)
      resp = conn.get("/v1/buildUploads/#{@build_upload.remote_id}") do |req|
        req.headers["Authorization"] = "Bearer #{jwt}"
      end
      raise AppleError, "GET /buildUploads failed #{resp.status}" unless resp.status.between?(200, 299)
      JSON.parse(resp.body)
    end

    def conn
      @conn ||= Faraday.new(BASE_URL) do |f|
        f.options.timeout      = 20
        f.options.open_timeout = 20
        f.adapter Faraday.default_adapter
      end
    end
  end
end
