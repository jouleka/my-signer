require "stringio"
require "googleauth"
require "google/apis/androidpublisher_v3"

module GooglePlay
  class Client
    SCOPE = "https://www.googleapis.com/auth/androidpublisher".freeze

    def initialize(credential:, timeout: 30)
      @credential = credential
      validate_credential!

      @auth = build_authorization

      @service = Google::Apis::AndroidpublisherV3::AndroidPublisherService.new
      @service.authorization = @auth
      @service.client_options.open_timeout_sec = timeout
      @service.client_options.read_timeout_sec = timeout
      @service.request_options.retries = 3
    end

    attr_reader :service

    # Basic connectivity check: ensures we can obtain an access token
    def ping!
      @auth.fetch_access_token!
      true
    end

    # ---- Edits ----
    def create_edit(package_name)
      edit = Google::Apis::AndroidpublisherV3::AppEdit.new
      @service.insert_edit(package_name, edit)
    end

    def commit_edit(package_name, edit_id, changes_not_sent_for_review: true)
      @service.commit_edit(package_name, edit_id, changes_not_sent_for_review: changes_not_sent_for_review)
    end

    def delete_edit(package_name, edit_id)
      @service.delete_edit(package_name, edit_id)
    end

    # ---- Uploads ----
    def upload_aab(package_name, edit_id, aab_path)
      @service.upload_edit_bundle(
        package_name,
        edit_id,
        upload_source: aab_path,
        content_type: "application/octet-stream"
      )
    end

    def upload_apk(package_name, edit_id, apk_path)
      @service.upload_edit_apk(
        package_name,
        edit_id,
        upload_source: apk_path,
        content_type: "application/vnd.android.package-archive"
      )
    end

    # ---- Tracks ----
    def list_tracks(package_name, edit_id)
      @service.list_edit_tracks(package_name, edit_id)
    end

    def get_track(package_name, edit_id, track)
      @service.get_edit_track(package_name, edit_id, track)
    end

    # ---- Builds ----

    def list_apks(package_name, edit_id)
      @service.list_edit_apks(package_name, edit_id)
    end

    def list_bundles(package_name, edit_id)
      @service.list_edit_bundles(package_name, edit_id)
    end

    def get_apk(package_name, edit_id, version_code)
      @service.get_edit_apk(package_name, edit_id, version_code)
    end

    def get_bundle(package_name, edit_id, version_code)
      @service.get_edit_bundle(package_name, edit_id, version_code)
    end

    # releases: Array<Google::Apis::AndroidpublisherV3::TrackRelease>
    def update_track(package_name, edit_id, track, releases: [])
      track_obj = Google::Apis::AndroidpublisherV3::Track.new(
        track: track,
        releases: releases
      )
      @service.update_edit_track(package_name, edit_id, track, track_obj)
    end

    # ---- Metadata / helpers ----

    def fetch_app_details(package_name, edit_id)
      @service.get_edit_detail(package_name, edit_id)
    end

    def list_app_listings(package_name, edit_id)
      @service.list_edit_listings(package_name, edit_id)
    end

    def get_app_listing(package_name, edit_id, language)
      @service.get_edit_listing(package_name, edit_id, language)
    end

    def update_app_listing(package_name, edit_id, language, listing)
      @service.update_edit_listing(package_name, edit_id, language, listing)
    end

    def list_all_users(developer_account_id)
      parent = "developers/#{developer_account_id}"
      users = []
      page_token = nil

      loop do
        resp = @service.list_users(parent, page_size: -1, page_token: page_token)
        users.concat(resp.users) if resp&.users
        page_token = resp&.next_page_token
        break if page_token.blank?
      end

      users
    end

    private

    def build_authorization
      json = @credential.service_account_json
      raise "Missing service_account_json" if json.to_s.strip.empty?
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(json),
        scope: SCOPE
      )
    end

    def validate_credential!
      raise "Credential inactive" if @credential.respond_to?(:active?) && !@credential.active?
    end
  end
end
