class AddCliDefaultsToAppleApps < ActiveRecord::Migration[8.0]
  # CLI release defaults migrate from the legacy AppStoreRelease model
  # (keyed on apple_bundle_id) to a JSONB column on apple_apps (keyed on app).
  # The backfill joins via the bundle identifier string so an AppStoreRelease
  # whose bundle_id_record matches an apple_app.bundle_id migrates cleanly.
  #
  # Content fields (whats_new, promotional_text, support_url, marketing_url,
  # privacy_policy_url) live on StoreListing — we ONLY copy them into the
  # primary-locale StoreListing here if the StoreListing doesn't already have
  # them, so we don't clobber fresher listing data.

  CLI_KEYS = %w[
    release_type
    earliest_release_date
    auto_submit
    phased_release
    version_string
    build_number
    localizations
  ].freeze

  CONTENT_KEYS = %w[
    whats_new
    promotional_text
    support_url
    marketing_url
    privacy_policy_url
  ].freeze

  def up
    add_column :apple_apps, :cli_defaults, :jsonb, default: {}, null: false

    # Backfill cli_defaults from app_store_releases, and rescue orphaned
    # content into the matching primary-locale StoreListing when possible.
    # Using raw SQL to avoid coupling to the AppStoreRelease / StoreListing
    # models (which may change between now and when this migration runs).
    return unless table_exists?(:app_store_releases)

    # We emit `localizations` ONLY when the source has a non-empty array.
    # Otherwise jsonb_strip_nulls below would leave `{"localizations": []}` on
    # apps that had an AppStoreRelease row with all columns null — making them
    # look "configured" and triggering 409 conflicts on subsequent API creates.
    execute(<<~SQL)
      UPDATE apple_apps aa
      SET cli_defaults = jsonb_strip_nulls(jsonb_build_object(
        'release_type',           asr.release_type,
        'earliest_release_date',  to_char(asr.earliest_release_date AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'auto_submit',            asr.auto_submit,
        'phased_release',         asr.phased_release,
        'version_string',         asr.version_string,
        'build_number',           asr.build_number,
        'localizations',          CASE
                                    WHEN asr.localizations IS NOT NULL
                                         AND jsonb_typeof(asr.localizations) = 'array'
                                         AND jsonb_array_length(asr.localizations) > 0
                                    THEN asr.localizations
                                    ELSE NULL
                                  END
      ))
      FROM app_store_releases asr
      INNER JOIN apple_bundle_ids abi ON abi.id = asr.apple_bundle_id_id
      WHERE aa.bundle_id = abi.identifier
        AND aa.organization_id = abi.organization_id
    SQL

    # Rescue orphaned content into StoreListing (primary locale for the app).
    # Only writes fields that are NULL/blank on the StoreListing so we never
    # overwrite fresher data.
    CONTENT_KEYS.each do |field|
      execute(<<~SQL)
        UPDATE store_listings sl
        SET #{field} = asr.#{field}
        FROM app_store_releases asr
        INNER JOIN apple_bundle_ids abi ON abi.id = asr.apple_bundle_id_id
        INNER JOIN apple_apps aa ON aa.bundle_id = abi.identifier AND aa.organization_id = abi.organization_id
        WHERE sl.listable_type = 'AppleApp'
          AND sl.listable_id = aa.id
          AND sl.locale = COALESCE(NULLIF(aa.raw_json->'attributes'->>'primaryLocale', ''), 'en-US')
          AND COALESCE(asr.#{field}, '') <> ''
          AND COALESCE(sl.#{field}, '') = ''
      SQL
    end
  end

  def down
    remove_column :apple_apps, :cli_defaults
  end
end
