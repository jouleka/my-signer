module StoreListingSync
  class GooglePusher
    # Pushes local StoreListing changes to Google Play.
    # Uses the edits/commit pattern required by the Google Play API.

    def initialize(organization:, store_listing:)
      @organization = organization
      @store_listing = store_listing
      @android_app = store_listing.listable
      @credential = organization.google_play_credentials.find_by(active: true)
      raise "No active Google Play credential" unless @credential
      raise "Store listing is not for an Android app" unless store_listing.android?
    end

    # @return [Hash] Push result with :status, :pushed_fields, :skipped_fields
    #
    # NOTE: Google Play allows only ONE open edit per service account at a time.
    # If multiple push jobs run concurrently for the same app, the second
    # create_edit call will invalidate the first. Consider serializing pushes
    # per package_name if concurrent execution is possible.
    def push!
      client = GooglePlay::Client.new(credential: @credential)
      listings_service = GooglePlay::Listings.new(client)

      @pushed_fields = []
      @skipped_fields = []

      %w[app_name short_description description].each do |field|
        if @store_listing.send(field).present?
          @pushed_fields << field
        elsif @store_listing.send(field).nil? && field != "app_name"
          # nil fields are not sent to the store, so they may still have old values
          @skipped_fields << field
        end
      end

      listings_service.update(
        @android_app.package_name,
        locale: @store_listing.locale,
        title: @store_listing.app_name,
        short_description: @store_listing.short_description,
        full_description: @store_listing.description
      )

      # Push release notes (whats_new) via the tracks/releases API.
      # This is a separate edit session because release notes live on track
      # releases, not on store listings.
      push_release_notes!(client)

      @store_listing.update!(
        sync_status: "synced",
        last_synced_at: Time.current,
        push_status: "success",
        push_error: nil,
        push_fields_skipped: @skipped_fields,
        last_pushed_at: Time.current
      )

      { status: "success", pushed_fields: @pushed_fields, skipped_fields: @skipped_fields }
    end

    private

    # Push whats_new text as release notes on the production track.
    # Release notes in Google Play are per-release on a track (not part of
    # the listings API), so this opens its own edit session.
    #
    # Best-effort: if it fails (e.g., no active release on production),
    # the error is logged and whats_new is added to skipped_fields.
    def push_release_notes!(client)
      return unless @store_listing.whats_new.present?

      package_name = @android_app.package_name
      edit = nil

      begin
        edit = client.create_edit(package_name)

        # Get the production track
        track = client.get_track(package_name, edit.id, "production")
        releases = track.releases

        if releases.blank?
          Rails.logger.info("GooglePusher: No releases on production track — skipping whats_new")
          client.delete_edit(package_name, edit.id)
          @skipped_fields << "whats_new"
          return
        end

        # Find a release to attach notes to (completed, inProgress, or draft)
        active_release = releases.find { |r| r.status.in?(%w[completed inProgress draft]) }

        unless active_release
          Rails.logger.info("GooglePusher: No active/draft release on production — skipping whats_new")
          client.delete_edit(package_name, edit.id)
          @skipped_fields << "whats_new"
          return
        end

        # Build localized release notes — merge with existing notes,
        # replacing any existing entry for this locale
        existing_notes = active_release.release_notes || []
        other_notes = existing_notes.reject { |n| n.language == @store_listing.locale }

        new_note = Google::Apis::AndroidpublisherV3::LocalizedText.new
        new_note.language = @store_listing.locale
        new_note.text = @store_listing.whats_new

        active_release.release_notes = other_notes + [ new_note ]

        # Preserve ALL releases on the track — update_track is a full replacement,
        # so passing only the modified release would drop other releases (drafts, staged rollouts, etc.)
        # No need to map — active_release was mutated in-place and is already in the releases array.
        client.update_track(package_name, edit.id, "production", releases: releases)
        client.commit_edit(package_name, edit.id)

        @pushed_fields << "whats_new"
      rescue StandardError => e
        # Best-effort: log the failure and clean up the edit
        Rails.logger.warn("GooglePusher: Failed to push release notes - #{e.message}")
        begin
          client.delete_edit(package_name, edit.id) if edit
        rescue StandardError
          nil
        end
        @skipped_fields << "whats_new"
      end
    end
  end
end
