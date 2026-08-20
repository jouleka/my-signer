require "faraday"
require "json"

module AppStoreConnect
  class BuildUploadCreator
    class Error < StandardError; end
    class AppleError < Error
      attr_reader :status, :apple_body
      def initialize(msg, status:, apple_body:)
        super(msg); @status = status; @apple_body = apple_body
      end
    end
    class DuplicatePending < Error; end

    BASE_URL = "https://api.appstoreconnect.apple.com"

    def initialize(credential:, params:)
      @credential = credential
      @params     = params
    end

    def call
      guard_against_duplicate_pending!
      jwt = JwtMinter.for(@credential)

      upload_remote = post_json!(jwt, "/v1/buildUploads", build_upload_body)
      file_remote   = post_json!(jwt, "/v1/buildUploadFiles", build_upload_file_body(upload_remote["data"]["id"]))

      row = AscBuildUpload.create!(
        organization:                    @params[:apple_app].organization,
        apple_app:                       @params[:apple_app],
        user:                            @params[:user],
        remote_id:                       upload_remote["data"]["id"],
        remote_file_id:                  file_remote["data"]["id"],
        cf_bundle_version:               @params[:cf_bundle_version],
        cf_bundle_short_version_string:  @params[:cf_bundle_short_version_string],
        platform:                        @params[:platform],
        file_name:                       @params[:file_name],
        file_size:                       @params[:file_size],
        state:                           "pending"
      )

      {
        build_upload:      row,
        upload_operations: file_remote["data"]["attributes"]["uploadOperations"]
      }
    end

    private

    def guard_against_duplicate_pending!
      scope = AscBuildUpload.where(
        organization:      @params[:apple_app].organization,
        apple_app:         @params[:apple_app],
        cf_bundle_version: @params[:cf_bundle_version],
        state:             "pending"
      ).where("created_at > ?", 10.minutes.ago)
      if scope.exists?
        raise DuplicatePending, "A pending upload exists for this app+version within the last 10 minutes."
      end
    end

    def build_upload_body
      {
        data: {
          type: "buildUploads",
          attributes: {
            cfBundleVersion:            @params[:cf_bundle_version],
            cfBundleShortVersionString: @params[:cf_bundle_short_version_string],
            platform:                   @params[:platform]
          },
          relationships: {
            app: { data: { type: "apps", id: @params[:apple_app].app_store_id } }
          }
        }
      }
    end

    def build_upload_file_body(remote_upload_id)
      {
        data: {
          type: "buildUploadFiles",
          attributes: {
            fileName:   @params[:file_name],
            fileSize:   @params[:file_size],
            uti:        "com.apple.ipa",
            assetType:  "ASSET"
          },
          relationships: {
            buildUpload: { data: { type: "buildUploads", id: remote_upload_id } }
          }
        }
      }
    end

    def post_json!(jwt, path, body)
      conn = Faraday.new(BASE_URL) do |f|
        f.options.timeout      = 20
        f.options.open_timeout = 20
        f.adapter Faraday.default_adapter
      end
      resp = conn.post(path) do |req|
        req.headers["Authorization"] = "Bearer #{jwt}"
        req.headers["Content-Type"]  = "application/json"
        req.body = body.to_json
      end
      if resp.status.between?(200, 299)
        JSON.parse(resp.body)
      else
        raise AppleError.new("ASC #{path} returned #{resp.status}", status: resp.status, apple_body: resp.body)
      end
    end
  end
end
