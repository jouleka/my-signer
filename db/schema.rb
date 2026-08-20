# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_20_153108) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "android_apps", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "package_name", null: false
    t.string "name"
    t.string "default_language"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "cli_defaults", default: {}, null: false
    t.index ["organization_id", "package_name"], name: "index_android_apps_on_organization_id_and_package_name", unique: true
    t.index ["organization_id"], name: "index_android_apps_on_organization_id"
  end

  create_table "android_builds", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "android_app_id", null: false
    t.string "version_code", null: false
    t.string "version_name"
    t.string "binary_sha256"
    t.string "binary_sha1"
    t.string "status"
    t.integer "minimum_sdk_version"
    t.integer "target_sdk_version"
    t.jsonb "native_code", default: []
    t.bigint "file_size_bytes"
    t.datetime "uploaded_at"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["android_app_id", "version_code"], name: "index_android_builds_on_android_app_id_and_version_code", unique: true
    t.index ["android_app_id"], name: "index_android_builds_on_android_app_id"
    t.index ["organization_id", "android_app_id"], name: "index_android_builds_on_organization_id_and_android_app_id"
    t.index ["organization_id"], name: "index_android_builds_on_organization_id"
  end

  create_table "android_keystores", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "android_app_id"
    t.string "name", null: false
    t.string "key_alias"
    t.date "expires_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "fingerprint_sha256"
    t.uuid "vault_record_id", default: -> { "gen_random_uuid()" }, null: false
    t.text "keystore_file_envelope"
    t.text "keystore_password_envelope"
    t.text "key_password_envelope"
    t.index ["android_app_id"], name: "index_android_keystores_on_android_app_id"
    t.index ["organization_id", "active"], name: "index_android_keystores_on_organization_id_and_active"
    t.index ["organization_id", "android_app_id"], name: "idx_unique_active_keystore_per_org_app", unique: true, where: "((active = true) AND (android_app_id IS NOT NULL))"
    t.index ["organization_id", "fingerprint_sha256"], name: "idx_android_keystores_org_fingerprint_unique", unique: true
    t.index ["organization_id", "name"], name: "index_android_keystores_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_android_keystores_on_organization_id"
    t.index ["vault_record_id"], name: "index_android_keystores_on_vault_record_id", unique: true
  end

  create_table "android_tracks", force: :cascade do |t|
    t.bigint "android_app_id", null: false
    t.string "track_name", null: false
    t.string "status"
    t.jsonb "releases", default: {}
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["android_app_id", "track_name"], name: "index_android_tracks_on_android_app_id_and_track_name", unique: true
    t.index ["android_app_id"], name: "index_android_tracks_on_android_app_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.text "scopes", default: "read"
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.boolean "revoked", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "revoked_at"
    t.index ["organization_id", "revoked"], name: "index_api_tokens_on_organization_id_and_revoked"
    t.index ["organization_id"], name: "index_api_tokens_on_organization_id"
    t.index ["revoked_at"], name: "index_api_tokens_on_revoked_at"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id", "revoked"], name: "index_api_tokens_on_user_id_and_revoked"
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "app_analytics_snapshots", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "snapshotable_type", null: false
    t.bigint "snapshotable_id", null: false
    t.date "snapshot_date", null: false
    t.integer "first_time_downloads", default: 0
    t.integer "redownloads", default: 0
    t.integer "total_downloads", default: 0
    t.integer "impressions", default: 0
    t.integer "product_page_views", default: 0
    t.integer "updates", default: 0
    t.decimal "conversion_rate", precision: 5, scale: 2
    t.integer "sessions", default: 0
    t.integer "active_devices", default: 0
    t.integer "crashes", default: 0
    t.decimal "crash_rate", precision: 8, scale: 6
    t.decimal "anr_rate", precision: 8, scale: 6
    t.string "data_source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "retention_day_1", precision: 5, scale: 2
    t.decimal "retention_day_7", precision: 5, scale: 2
    t.decimal "retention_day_14", precision: 5, scale: 2
    t.decimal "retention_day_28", precision: 5, scale: 2
    t.integer "active_subscriptions", default: 0
    t.integer "new_subscriptions", default: 0
    t.integer "churned_subscriptions", default: 0
    t.integer "trial_starts", default: 0
    t.integer "trial_conversions", default: 0
    t.decimal "proceeds", precision: 10, scale: 2
    t.integer "installs", default: 0
    t.integer "deletions", default: 0
    t.index ["organization_id", "snapshot_date"], name: "idx_on_organization_id_snapshot_date_df31e2e4ce"
    t.index ["organization_id"], name: "index_app_analytics_snapshots_on_organization_id"
    t.index ["snapshotable_type", "snapshotable_id", "snapshot_date"], name: "idx_analytics_snapshots_app_date", unique: true
  end

  create_table "app_releases", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "listable_type", null: false
    t.bigint "listable_id", null: false
    t.string "version_string"
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["listable_type", "listable_id"], name: "idx_app_releases_listable"
    t.index ["organization_id", "listable_type", "listable_id", "version_string"], name: "idx_app_releases_org_app_version", unique: true
    t.index ["organization_id"], name: "index_app_releases_on_organization_id"
    t.index ["status"], name: "index_app_releases_on_status"
  end

  create_table "app_reviews", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "reviewable_type", null: false
    t.bigint "reviewable_id", null: false
    t.string "remote_id", null: false
    t.integer "rating", null: false
    t.string "title"
    t.text "body", null: false
    t.string "reviewer_name"
    t.string "territory"
    t.string "language"
    t.datetime "reviewed_at", null: false
    t.string "sentiment", default: "neutral"
    t.text "reply_text"
    t.datetime "reply_posted_at"
    t.string "reply_status", default: "none"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "reviewed_at"], name: "index_app_reviews_on_organization_id_and_reviewed_at"
    t.index ["organization_id", "sentiment"], name: "index_app_reviews_on_organization_id_and_sentiment"
    t.index ["organization_id"], name: "index_app_reviews_on_organization_id"
    t.index ["reviewable_type", "reviewable_id", "remote_id"], name: "idx_app_reviews_reviewable_remote", unique: true
    t.index ["reviewable_type", "reviewable_id"], name: "index_app_reviews_on_reviewable"
  end

  create_table "app_store_connect_credentials", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name"
    t.string "key_id"
    t.string "issuer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.datetime "last_synced_at"
    t.string "last_sync_status"
    t.text "last_sync_error"
    t.string "team_id"
    t.uuid "vault_record_id", default: -> { "gen_random_uuid()" }, null: false
    t.text "private_key_envelope"
    t.index ["organization_id", "active"], name: "index_asc_credentials_on_org_and_active"
    t.index ["organization_id", "name"], name: "index_asc_credentials_on_org_and_name", unique: true
    t.index ["organization_id"], name: "index_app_store_connect_credentials_on_organization_id"
    t.index ["vault_record_id"], name: "index_app_store_connect_credentials_on_vault_record_id", unique: true
  end

  create_table "app_store_versions", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "apple_app_id", null: false
    t.bigint "apple_build_id"
    t.string "version_id", null: false
    t.string "version_string"
    t.string "platform"
    t.string "app_store_state"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "phased_release_pending", default: false, null: false
    t.jsonb "issues", default: [], null: false
    t.datetime "issues_synced_at"
    t.string "submission_status"
    t.text "submission_error"
    t.index ["apple_app_id", "version_string"], name: "index_app_store_versions_on_apple_app_id_and_version_string"
    t.index ["apple_app_id"], name: "index_app_store_versions_on_apple_app_id"
    t.index ["apple_build_id"], name: "index_app_store_versions_on_apple_build_id"
    t.index ["organization_id"], name: "index_app_store_versions_on_organization_id"
    t.index ["phased_release_pending"], name: "index_app_store_versions_on_phased_pending", where: "(phased_release_pending = true)"
    t.index ["submission_status"], name: "index_app_store_versions_on_submitting", where: "((submission_status)::text = 'submitting'::text)"
    t.index ["version_id"], name: "index_app_store_versions_on_version_id", unique: true
  end

  create_table "apple_ads_credentials", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "client_id"
    t.string "team_id"
    t.string "key_id"
    t.datetime "last_successful_at"
    t.string "last_error", limit: 200
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "vault_record_id", default: -> { "gen_random_uuid()" }, null: false
    t.text "private_key_pem_envelope"
    t.index ["organization_id"], name: "index_apple_ads_credentials_on_organization_id", unique: true
    t.index ["vault_record_id"], name: "index_apple_ads_credentials_on_vault_record_id", unique: true
  end

  create_table "apple_ads_recommendations", force: :cascade do |t|
    t.bigint "apple_app_id", null: false
    t.string "keyword", limit: 100, null: false
    t.integer "search_popularity", null: false
    t.datetime "search_popularity_updated_at", null: false
    t.bigint "bid_amount_micros"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_app_id", "keyword"], name: "index_apple_ads_recommendations_on_apple_app_id_and_keyword", unique: true
    t.index ["apple_app_id", "search_popularity"], name: "idx_recs_by_popularity", order: { search_popularity: :desc }
    t.index ["apple_app_id"], name: "index_apple_ads_recommendations_on_apple_app_id"
  end

  create_table "apple_app_groups", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "identifier", null: false
    t.string "name"
    t.string "team_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "identifier"], name: "index_apple_app_groups_on_organization_id_and_identifier", unique: true
    t.index ["organization_id", "team_id"], name: "index_apple_app_groups_on_organization_id_and_team_id"
    t.index ["organization_id"], name: "index_apple_app_groups_on_organization_id"
  end

  create_table "apple_apps", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "app_store_id", null: false
    t.string "bundle_id"
    t.string "name"
    t.string "sku"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "cli_defaults", default: {}, null: false
    t.index ["app_store_id"], name: "index_apple_apps_on_app_store_id", unique: true
    t.index ["organization_id", "bundle_id"], name: "index_apple_apps_on_organization_id_and_bundle_id"
    t.index ["organization_id", "sku"], name: "index_apple_apps_on_organization_id_and_sku", unique: true
    t.index ["organization_id"], name: "index_apple_apps_on_organization_id"
  end

  create_table "apple_builds", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "apple_app_id", null: false
    t.string "build_id", null: false
    t.string "version"
    t.string "build_number"
    t.string "processing_state"
    t.datetime "uploaded_date"
    t.datetime "expires_at"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_app_id", "version", "build_number"], name: "idx_on_apple_app_id_version_build_number_95f711f11c"
    t.index ["apple_app_id"], name: "index_apple_builds_on_apple_app_id"
    t.index ["build_id"], name: "index_apple_builds_on_build_id", unique: true
    t.index ["organization_id"], name: "index_apple_builds_on_organization_id"
  end

  create_table "apple_bundle_id_app_groups", force: :cascade do |t|
    t.bigint "apple_bundle_id_id", null: false
    t.bigint "apple_app_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_app_group_id"], name: "index_apple_bundle_id_app_groups_on_apple_app_group_id"
    t.index ["apple_bundle_id_id", "apple_app_group_id"], name: "idx_bundle_app_group_unique", unique: true
    t.index ["apple_bundle_id_id"], name: "index_apple_bundle_id_app_groups_on_apple_bundle_id_id"
  end

  create_table "apple_bundle_id_capabilities", force: :cascade do |t|
    t.bigint "apple_bundle_id_id", null: false
    t.string "remote_id", null: false
    t.string "capability_type", null: false
    t.jsonb "settings", default: {}
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_bundle_id_id", "capability_type"], name: "idx_bundle_id_capabilities_unique", unique: true
    t.index ["apple_bundle_id_id"], name: "index_apple_bundle_id_capabilities_on_apple_bundle_id_id"
  end

  create_table "apple_bundle_id_merchant_ids", force: :cascade do |t|
    t.bigint "apple_bundle_id_id", null: false
    t.bigint "apple_merchant_id_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_bundle_id_id", "apple_merchant_id_id"], name: "idx_bundle_merchant_unique", unique: true
    t.index ["apple_bundle_id_id"], name: "index_apple_bundle_id_merchant_ids_on_apple_bundle_id_id"
    t.index ["apple_merchant_id_id"], name: "index_apple_bundle_id_merchant_ids_on_apple_merchant_id_id"
  end

  create_table "apple_bundle_ids", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "remote_id", null: false
    t.string "identifier"
    t.string "name"
    t.string "platform"
    t.jsonb "raw_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "team_id"
    t.index ["organization_id", "identifier"], name: "index_apple_bundle_ids_on_organization_id_and_identifier"
    t.index ["organization_id", "remote_id"], name: "index_apple_bundle_ids_on_organization_id_and_remote_id", unique: true
    t.index ["organization_id", "team_id"], name: "index_apple_bundle_ids_on_organization_id_and_team_id"
    t.index ["organization_id"], name: "index_apple_bundle_ids_on_organization_id"
  end

  create_table "apple_certificates", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "remote_id", null: false
    t.string "name"
    t.string "certificate_type"
    t.string "serial_number"
    t.string "platform"
    t.string "status"
    t.datetime "expires_at"
    t.jsonb "raw_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "team_id"
    t.index ["organization_id", "expires_at"], name: "index_apple_certificates_on_organization_id_and_expires_at"
    t.index ["organization_id", "platform"], name: "index_apple_certificates_on_organization_id_and_platform"
    t.index ["organization_id", "remote_id"], name: "index_apple_certificates_on_organization_id_and_remote_id", unique: true
    t.index ["organization_id", "team_id"], name: "index_apple_certificates_on_organization_id_and_team_id"
    t.index ["organization_id"], name: "index_apple_certificates_on_organization_id"
  end

  create_table "apple_devices", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "remote_id", null: false
    t.string "name"
    t.string "udid"
    t.string "platform"
    t.string "device_class"
    t.string "status"
    t.datetime "added_at"
    t.jsonb "raw_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "team_id"
    t.index ["organization_id", "platform"], name: "index_apple_devices_on_organization_id_and_platform"
    t.index ["organization_id", "remote_id"], name: "index_apple_devices_on_organization_id_and_remote_id", unique: true
    t.index ["organization_id", "team_id"], name: "index_apple_devices_on_organization_id_and_team_id"
    t.index ["organization_id", "udid"], name: "index_apple_devices_on_organization_id_and_udid"
    t.index ["organization_id"], name: "index_apple_devices_on_organization_id"
  end

  create_table "apple_merchant_ids", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "remote_id", null: false
    t.string "identifier", null: false
    t.string "name"
    t.string "team_id"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "identifier"], name: "index_apple_merchant_ids_on_organization_id_and_identifier", unique: true
    t.index ["organization_id", "remote_id"], name: "index_apple_merchant_ids_on_organization_id_and_remote_id", unique: true
    t.index ["organization_id", "team_id"], name: "index_apple_merchant_ids_on_organization_id_and_team_id"
    t.index ["organization_id"], name: "index_apple_merchant_ids_on_organization_id"
  end

  create_table "apple_provisioning_profiles", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "remote_id", null: false
    t.string "name"
    t.string "uuid"
    t.string "profile_type"
    t.string "state"
    t.string "platform"
    t.string "bundle_id_identifier"
    t.datetime "expires_at"
    t.jsonb "raw_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "team_id"
    t.index ["organization_id", "expires_at"], name: "idx_on_organization_id_expires_at_867eeee4da"
    t.index ["organization_id", "platform"], name: "idx_on_organization_id_platform_9709bc2268"
    t.index ["organization_id", "remote_id"], name: "idx_on_organization_id_remote_id_1b54fae1d0", unique: true
    t.index ["organization_id", "team_id"], name: "idx_on_organization_id_team_id_3b63b2cc6b"
    t.index ["organization_id"], name: "index_apple_provisioning_profiles_on_organization_id"
  end

  create_table "asc_build_uploads", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "apple_app_id", null: false
    t.bigint "user_id"
    t.string "remote_id", null: false
    t.string "remote_file_id", null: false
    t.string "cf_bundle_version", null: false
    t.string "cf_bundle_short_version_string", null: false
    t.string "platform", null: false
    t.string "file_name", null: false
    t.bigint "file_size", null: false
    t.string "state", default: "pending", null: false
    t.string "apple_state"
    t.jsonb "apple_state_detail", default: {}
    t.string "last_error"
    t.datetime "uploaded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_app_id"], name: "index_asc_build_uploads_on_apple_app_id"
    t.index ["organization_id", "apple_app_id", "cf_bundle_version", "state"], name: "idx_unique_pending_asc_upload_per_app_version", unique: true, where: "((state)::text = 'pending'::text)"
    t.index ["organization_id", "created_at"], name: "index_asc_build_uploads_on_organization_id_and_created_at"
    t.index ["organization_id"], name: "index_asc_build_uploads_on_organization_id"
    t.index ["remote_id"], name: "index_asc_build_uploads_on_remote_id", unique: true
    t.index ["user_id"], name: "index_asc_build_uploads_on_user_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.bigint "organization_id"
    t.bigint "actor_id"
    t.string "action", null: false
    t.string "resource_type"
    t.bigint "resource_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_audit_events_on_action"
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["organization_id", "action", "created_at"], name: "index_audit_events_on_org_action_created", order: { created_at: :desc }
    t.index ["organization_id", "created_at"], name: "index_audit_events_on_organization_id_and_created_at", order: { created_at: :desc }
    t.index ["organization_id"], name: "index_audit_events_on_organization_id"
    t.index ["resource_type", "resource_id"], name: "index_audit_events_on_resource_type_and_resource_id"
  end

  create_table "billing_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.string "provider_subscription_id", null: false
    t.string "provider_plan_id"
    t.string "provider_product_id"
    t.string "status", default: "pending", null: false
    t.string "plan_tier", null: false
    t.string "billing_interval", null: false
    t.string "provider_customer_id"
    t.string "customer_email"
    t.datetime "started_at"
    t.datetime "current_period_started_at"
    t.datetime "current_period_ends_at"
    t.datetime "cancelled_at"
    t.datetime "last_synced_at"
    t.boolean "cancel_at_period_end", default: false, null: false
    t.jsonb "provider_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_subscription_id"], name: "index_billing_subscriptions_on_provider_and_subscription_id", unique: true
    t.index ["user_id", "created_at"], name: "index_billing_subscriptions_on_user_id_and_created_at"
    t.index ["user_id", "status"], name: "index_billing_subscriptions_on_user_id_and_status"
    t.index ["user_id"], name: "index_billing_subscriptions_on_user_id"
  end

  create_table "billing_webhook_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "verification_status", default: "pending", null: false
    t.datetime "processed_at"
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "event_id"], name: "index_billing_webhook_events_on_provider_and_event_id", unique: true
    t.index ["provider", "event_type"], name: "index_billing_webhook_events_on_provider_and_event_type"
  end

  create_table "custom_product_page_localizations", force: :cascade do |t|
    t.bigint "custom_product_page_version_id", null: false
    t.bigint "organization_id", null: false
    t.string "remote_id", null: false
    t.string "locale", null: false
    t.string "promotional_text"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["custom_product_page_version_id", "locale"], name: "idx_cpp_locs_version_locale", unique: true
    t.index ["custom_product_page_version_id"], name: "idx_on_custom_product_page_version_id_52c8ebb962"
    t.index ["organization_id"], name: "index_custom_product_page_localizations_on_organization_id"
    t.index ["remote_id"], name: "index_custom_product_page_localizations_on_remote_id", unique: true
  end

  create_table "custom_product_page_versions", force: :cascade do |t|
    t.bigint "custom_product_page_id", null: false
    t.bigint "organization_id", null: false
    t.string "remote_id", null: false
    t.string "state", default: "PREPARE_FOR_SUBMISSION", null: false
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "deep_link"
    t.string "submission_status"
    t.text "submission_error"
    t.index ["custom_product_page_id", "state"], name: "idx_cpp_versions_page_state"
    t.index ["custom_product_page_id"], name: "index_custom_product_page_versions_on_custom_product_page_id"
    t.index ["organization_id"], name: "index_custom_product_page_versions_on_organization_id"
    t.index ["remote_id"], name: "index_custom_product_page_versions_on_remote_id", unique: true
  end

  create_table "custom_product_pages", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "apple_app_id", null: false
    t.string "remote_id", null: false
    t.string "name", null: false
    t.boolean "visible", default: true, null: false
    t.jsonb "raw_json", default: {}
    t.jsonb "performance_data", default: {}
    t.datetime "performance_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_app_id", "name"], name: "index_custom_product_pages_on_apple_app_id_and_name"
    t.index ["apple_app_id"], name: "index_custom_product_pages_on_apple_app_id"
    t.index ["organization_id"], name: "index_custom_product_pages_on_organization_id"
    t.index ["remote_id"], name: "index_custom_product_pages_on_remote_id", unique: true
  end

  create_table "google_play_credentials", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name"
    t.string "developer_account_id"
    t.boolean "active", default: true, null: false
    t.datetime "last_synced_at"
    t.string "last_sync_status"
    t.text "last_sync_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "play_reporting_api_disabled_at"
    t.uuid "vault_record_id", default: -> { "gen_random_uuid()" }, null: false
    t.text "service_account_json_envelope"
    t.index ["organization_id", "active"], name: "index_google_play_credentials_on_organization_id_and_active"
    t.index ["organization_id", "developer_account_id"], name: "idx_unique_gp_dev_acc_per_org", unique: true, where: "(developer_account_id IS NOT NULL)"
    t.index ["organization_id", "name"], name: "index_google_play_credentials_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_google_play_credentials_on_organization_id"
    t.index ["vault_record_id"], name: "index_google_play_credentials_on_vault_record_id", unique: true
  end

  create_table "keyword_rankings", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "keyword", null: false
    t.integer "rank"
    t.date "checked_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "tracked_keyword_country_id"
    t.index ["organization_id", "checked_on"], name: "idx_keyword_rankings_on_org_and_checked_on"
    t.index ["organization_id"], name: "index_keyword_rankings_on_organization_id"
    t.index ["tracked_keyword_country_id", "checked_on"], name: "idx_kw_rankings_tkc_checked_on_unique", unique: true, where: "(tracked_keyword_country_id IS NOT NULL)"
    t.index ["tracked_keyword_country_id"], name: "index_keyword_rankings_on_tracked_keyword_country_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "organization_id", null: false
    t.integer "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_memberships_on_user_and_org_unique", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "organization_id"
    t.string "notification_type"
    t.string "title"
    t.text "message"
    t.string "resource_type"
    t.bigint "resource_id"
    t.datetime "read_at"
    t.datetime "dismissed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "notification_date"
    t.index ["organization_id"], name: "index_notifications_on_organization_id"
    t.index ["resource_type", "resource_id"], name: "index_notifications_on_resource"
    t.index ["user_id", "resource_type", "resource_id", "notification_type", "notification_date"], name: "idx_notifications_unique_per_day", unique: true
    t.index ["user_id", "resource_type", "resource_id", "notification_type", "notification_date"], name: "index_notifications_on_dedup_key", unique: true, where: "((notification_date IS NOT NULL) AND (resource_type IS NOT NULL) AND (resource_id IS NOT NULL))"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "org_sync_runs", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "job_name", null: false
    t.string "status", default: "running", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_name"], name: "index_org_sync_runs_on_job_name"
    t.index ["organization_id", "job_name"], name: "index_org_sync_runs_on_organization_id_and_job_name", unique: true
  end

  create_table "organization_invitations", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "inviter_id", null: false
    t.string "email", null: false
    t.integer "role", default: 1, null: false
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inviter_id"], name: "index_organization_invitations_on_inviter_id"
    t.index ["organization_id", "email", "accepted_at", "cancelled_at"], name: "index_org_invites_uniquish"
    t.index ["organization_id"], name: "index_organization_invitations_on_organization_id"
    t.index ["token"], name: "index_organization_invitations_on_token", unique: true
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name"
    t.bigint "owner_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "memberships_count", default: 0, null: false
    t.jsonb "brand_settings", default: {}
    t.string "access_state", default: "active", null: false
    t.datetime "access_blocked_at"
    t.string "access_block_reason"
    t.string "access_blocked_by_plan_tier"
    t.integer "ai_translations_count", default: 0, null: false
    t.datetime "ai_translations_reset_at"
    t.integer "ai_rewrites_count", default: 0, null: false
    t.datetime "ai_rewrites_reset_at"
    t.string "slug", null: false
    t.text "byok_kms_key_arn"
    t.index ["owner_id", "access_state"], name: "index_organizations_on_owner_id_and_access_state"
    t.index ["owner_id"], name: "index_organizations_on_owner_id"
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "play_store_releases", force: :cascade do |t|
    t.bigint "android_app_id", null: false
    t.string "track", default: "beta"
    t.text "release_notes"
    t.string "status_url"
    t.float "user_fraction"
    t.boolean "auto_submit", default: false
    t.jsonb "localizations", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "version_code", null: false
    t.string "status", default: "draft", null: false
    t.datetime "released_at"
    t.jsonb "issues", default: [], null: false
    t.datetime "issues_synced_at"
    t.index ["android_app_id", "version_code", "status"], name: "index_play_store_releases_on_app_version_status", unique: true
  end

  create_table "rating_snapshots", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "snapshotable_type", null: false
    t.bigint "snapshotable_id", null: false
    t.date "snapshot_date", null: false
    t.decimal "average_rating", precision: 3, scale: 2, null: false
    t.integer "review_count", default: 0
    t.integer "rating_1_count", default: 0
    t.integer "rating_2_count", default: 0
    t.integer "rating_3_count", default: 0
    t.integer "rating_4_count", default: 0
    t.integer "rating_5_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_rating_snapshots_on_organization_id"
    t.index ["snapshotable_type", "snapshotable_id", "snapshot_date"], name: "idx_rating_snapshots_snapshotable_date", unique: true
    t.index ["snapshotable_type", "snapshotable_id"], name: "index_rating_snapshots_on_snapshotable"
  end

  create_table "release_checklists", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "listable_type"
    t.bigint "listable_id"
    t.string "version_string"
    t.string "platform"
    t.jsonb "items", default: [], null: false
    t.boolean "all_required_complete", default: false, null: false
    t.jsonb "custom_items", default: [], null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_release_checklists_on_created_by_id"
    t.index ["organization_id", "listable_type", "listable_id", "version_string"], name: "idx_release_checklists_org_app_version", unique: true
    t.index ["organization_id", "platform"], name: "idx_release_checklists_org_platform"
    t.index ["organization_id"], name: "index_release_checklists_on_organization_id"
  end

  create_table "release_notes", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "listable_type", null: false
    t.bigint "listable_id", null: false
    t.string "version_string"
    t.string "build_number"
    t.string "status", default: "draft", null: false
    t.string "locale", default: "en-US", null: false
    t.jsonb "template_data", default: {}, null: false
    t.text "rendered_text"
    t.text "raw_input"
    t.string "source"
    t.jsonb "translations", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "created_by_id"
    t.datetime "applied_at"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "submitted_for_review_at"
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.text "review_comment"
    t.index ["created_by_id"], name: "index_release_notes_on_created_by_id"
    t.index ["listable_type", "listable_id", "version_string"], name: "idx_release_notes_app_version"
    t.index ["organization_id", "listable_type", "listable_id", "status"], name: "idx_release_notes_org_app_status"
    t.index ["organization_id"], name: "index_release_notes_on_organization_id"
    t.index ["reviewed_by_id"], name: "index_release_notes_on_reviewed_by_id"
    t.index ["status"], name: "index_release_notes_on_status"
    t.index ["submitted_for_review_at"], name: "index_release_notes_on_submitted_for_review_at"
  end

  create_table "review_response_templates", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.string "category", default: "general"
    t.text "body", null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "category"], name: "idx_on_organization_id_category_2857adcd69"
    t.index ["organization_id"], name: "index_review_response_templates_on_organization_id"
  end

  create_table "saved_keyword_ideas", force: :cascade do |t|
    t.bigint "apple_app_id", null: false
    t.string "keyword", limit: 100, null: false
    t.bigint "added_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["added_by_user_id"], name: "index_saved_keyword_ideas_on_added_by_user_id"
    t.index ["apple_app_id", "keyword"], name: "index_saved_keyword_ideas_on_apple_app_id_and_keyword", unique: true
    t.index ["apple_app_id"], name: "index_saved_keyword_ideas_on_apple_app_id"
  end

  create_table "screenshot_exports", force: :cascade do |t|
    t.bigint "screenshot_project_id", null: false
    t.string "resolution", null: false
    t.integer "scene_position", null: false
    t.string "locale"
    t.string "export_format", default: "standard"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["screenshot_project_id", "resolution", "scene_position", "locale"], name: "idx_screenshot_exports_unique_key", unique: true
    t.index ["screenshot_project_id"], name: "index_screenshot_exports_on_screenshot_project_id"
  end

  create_table "screenshot_projects", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.string "platform", null: false
    t.jsonb "settings", default: {}
    t.integer "scenes_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "locales", default: [], null: false
    t.string "template"
    t.index ["organization_id", "name"], name: "index_screenshot_projects_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_screenshot_projects_on_organization_id"
  end

  create_table "screenshot_scenes", force: :cascade do |t|
    t.bigint "screenshot_project_id", null: false
    t.integer "position", null: false
    t.string "caption_text"
    t.binary "source_image_data"
    t.string "source_image_content_type"
    t.string "source_image_filename"
    t.integer "source_image_width"
    t.integer "source_image_height"
    t.jsonb "overrides", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "subtitle_text"
    t.jsonb "locale_variants", default: {}, null: false
    t.index ["screenshot_project_id", "position"], name: "index_screenshot_scenes_on_screenshot_project_id_and_position"
    t.index ["screenshot_project_id"], name: "index_screenshot_scenes_on_screenshot_project_id"
  end

  create_table "screenshot_uploads", force: :cascade do |t|
    t.bigint "screenshot_project_id", null: false
    t.bigint "organization_id", null: false
    t.string "target", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "config", default: {}
    t.jsonb "progress", default: {}
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_screenshot_uploads_on_created_at"
    t.index ["organization_id", "status"], name: "index_screenshot_uploads_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_screenshot_uploads_on_organization_id"
    t.index ["screenshot_project_id"], name: "index_screenshot_uploads_on_screenshot_project_id"
  end

  create_table "sso_configurations", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "idp_entity_id", null: false
    t.string "idp_sso_target_url", null: false
    t.string "idp_slo_target_url"
    t.text "idp_cert"
    t.string "name_identifier_format", default: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress", null: false
    t.jsonb "attribute_mappings", default: {}, null: false
    t.integer "jit_default_role", default: 1, null: false
    t.boolean "enforced", default: false, null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "verified_domains", default: [], null: false, array: true
    t.index ["organization_id"], name: "index_sso_configurations_on_organization_id", unique: true
  end

  create_table "store_listings", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "listable_type", null: false
    t.bigint "listable_id", null: false
    t.string "locale", null: false
    t.string "app_name"
    t.string "subtitle"
    t.string "keywords"
    t.string "short_description"
    t.text "description"
    t.text "promotional_text"
    t.text "whats_new"
    t.string "support_url"
    t.string "marketing_url"
    t.string "privacy_policy_url"
    t.jsonb "metadata", default: {}
    t.string "sync_status", default: "draft", null: false
    t.string "translation_status"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "push_status"
    t.string "push_error"
    t.jsonb "push_fields_skipped", default: []
    t.datetime "last_pushed_at"
    t.index ["listable_type", "listable_id", "locale"], name: "idx_store_listings_listable_locale", unique: true
    t.index ["listable_type", "listable_id"], name: "index_store_listings_on_listable"
    t.index ["organization_id", "listable_type"], name: "idx_store_listings_org_type"
    t.index ["organization_id"], name: "index_store_listings_on_organization_id"
    t.index ["sync_status"], name: "index_store_listings_on_sync_status"
  end

  create_table "testflight_beta_groups", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "apple_app_id", null: false
    t.string "remote_id", null: false
    t.string "name"
    t.boolean "public_link_enabled", default: false, null: false
    t.string "public_link"
    t.boolean "is_internal_group", default: false, null: false
    t.integer "tester_count", default: 0, null: false
    t.datetime "created_at_remote"
    t.jsonb "raw_json", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "testers", default: []
    t.index ["apple_app_id"], name: "index_testflight_beta_groups_on_apple_app_id"
    t.index ["organization_id", "remote_id"], name: "index_testflight_beta_groups_on_organization_id_and_remote_id", unique: true
    t.index ["organization_id"], name: "index_testflight_beta_groups_on_organization_id"
  end

  create_table "tracked_keyword_countries", force: :cascade do |t|
    t.bigint "tracked_keyword_id", null: false
    t.string "country", limit: 2, null: false
    t.datetime "last_checked_at"
    t.integer "current_rank"
    t.integer "previous_rank"
    t.integer "competition_count"
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country", "last_checked_at"], name: "index_tracked_keyword_countries_on_country_and_last_checked_at"
    t.index ["tracked_keyword_id", "country"], name: "idx_on_tracked_keyword_id_country_71e8da9f28", unique: true
    t.index ["tracked_keyword_id"], name: "index_tracked_keyword_countries_on_tracked_keyword_id"
  end

  create_table "tracked_keywords", force: :cascade do |t|
    t.bigint "apple_app_id", null: false
    t.string "keyword", limit: 100, null: false
    t.integer "search_popularity"
    t.datetime "search_popularity_updated_at"
    t.string "search_popularity_source", default: "apple_ads_recommendations", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["apple_app_id", "keyword"], name: "index_tracked_keywords_on_apple_app_id_and_keyword", unique: true
    t.index ["apple_app_id"], name: "index_tracked_keywords_on_apple_app_id"
  end

  create_table "trial_histories", force: :cascade do |t|
    t.string "email_hash", null: false
    t.datetime "started_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_hash"], name: "index_trial_histories_on_email_hash", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.string "provider"
    t.string "uid"
    t.string "name"
    t.string "avatar_url"
    t.bigint "last_organization_id"
    t.boolean "email_notifications_enabled", default: true, null: false
    t.boolean "notify_certificate_expiry", default: true, null: false
    t.boolean "notify_profile_expiry", default: true, null: false
    t.boolean "notify_keystore_expiry", default: true, null: false
    t.integer "notification_days_before", default: 30, null: false
    t.boolean "notify_sync_failures", default: true, null: false
    t.boolean "notify_sync_changes", default: false, null: false
    t.boolean "notify_revocations", default: true, null: false
    t.boolean "notify_team_activity", default: true, null: false
    t.integer "plan_tier", default: 0, null: false
    t.datetime "onboarding_completed_at"
    t.integer "onboarding_step", default: 0, null: false
    t.string "onboarding_platform"
    t.datetime "trial_started_at"
    t.datetime "trial_ends_at"
    t.jsonb "trial_reminders_sent", default: {}, null: false
    t.boolean "notify_member_activity", default: true, null: false
    t.boolean "notify_api_token_activity", default: true, null: false
    t.boolean "notify_sso_activity", default: true, null: false
    t.boolean "notify_security_alerts", default: true, null: false
    t.boolean "notify_billing_changes", default: true, null: false
    t.boolean "notify_release_activity", default: true, null: false
    t.boolean "notify_audit_digest", default: false, null: false
    t.datetime "terms_accepted_at"
    t.boolean "marketing_emails_opt_in", default: false, null: false
    t.datetime "deleted_at"
    t.string "deletion_token"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["deletion_token"], name: "index_users_on_deletion_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_organization_id"], name: "index_users_on_last_organization_id"
    t.index ["plan_tier"], name: "index_users_on_plan_tier"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid_unique", unique: true, where: "((provider IS NOT NULL) AND ((provider)::text <> ''::text) AND (uid IS NOT NULL) AND ((uid)::text <> ''::text))"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["trial_ends_at"], name: "index_users_on_trial_ends_at"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.check_constraint "deleted_at IS NULL AND deletion_token IS NULL OR deleted_at IS NOT NULL AND deletion_token IS NOT NULL", name: "users_deletion_pair_consistent"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "android_apps", "organizations"
  add_foreign_key "android_builds", "android_apps"
  add_foreign_key "android_builds", "organizations"
  add_foreign_key "android_keystores", "android_apps"
  add_foreign_key "android_keystores", "organizations"
  add_foreign_key "android_tracks", "android_apps"
  add_foreign_key "api_tokens", "organizations"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "app_analytics_snapshots", "organizations"
  add_foreign_key "app_releases", "organizations"
  add_foreign_key "app_reviews", "organizations"
  add_foreign_key "app_store_connect_credentials", "organizations"
  add_foreign_key "app_store_versions", "apple_apps"
  add_foreign_key "app_store_versions", "apple_builds"
  add_foreign_key "app_store_versions", "organizations"
  add_foreign_key "apple_ads_credentials", "organizations"
  add_foreign_key "apple_ads_recommendations", "apple_apps"
  add_foreign_key "apple_app_groups", "organizations"
  add_foreign_key "apple_apps", "organizations"
  add_foreign_key "apple_builds", "apple_apps"
  add_foreign_key "apple_builds", "organizations"
  add_foreign_key "apple_bundle_id_app_groups", "apple_app_groups"
  add_foreign_key "apple_bundle_id_app_groups", "apple_bundle_ids"
  add_foreign_key "apple_bundle_id_capabilities", "apple_bundle_ids"
  add_foreign_key "apple_bundle_id_merchant_ids", "apple_bundle_ids"
  add_foreign_key "apple_bundle_id_merchant_ids", "apple_merchant_ids"
  add_foreign_key "apple_bundle_ids", "organizations"
  add_foreign_key "apple_certificates", "organizations"
  add_foreign_key "apple_devices", "organizations"
  add_foreign_key "apple_merchant_ids", "organizations"
  add_foreign_key "apple_provisioning_profiles", "organizations"
  add_foreign_key "asc_build_uploads", "apple_apps"
  add_foreign_key "asc_build_uploads", "organizations"
  add_foreign_key "asc_build_uploads", "users", on_delete: :nullify
  add_foreign_key "audit_events", "organizations", on_delete: :nullify
  add_foreign_key "audit_events", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "billing_subscriptions", "users"
  add_foreign_key "custom_product_page_localizations", "custom_product_page_versions"
  add_foreign_key "custom_product_page_localizations", "organizations"
  add_foreign_key "custom_product_page_versions", "custom_product_pages"
  add_foreign_key "custom_product_page_versions", "organizations"
  add_foreign_key "custom_product_pages", "apple_apps"
  add_foreign_key "custom_product_pages", "organizations"
  add_foreign_key "google_play_credentials", "organizations"
  add_foreign_key "keyword_rankings", "organizations"
  add_foreign_key "keyword_rankings", "tracked_keyword_countries", on_delete: :nullify
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "notifications", "organizations"
  add_foreign_key "notifications", "users"
  add_foreign_key "org_sync_runs", "organizations", on_delete: :cascade
  add_foreign_key "organization_invitations", "organizations"
  add_foreign_key "organization_invitations", "users", column: "inviter_id"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "play_store_releases", "android_apps"
  add_foreign_key "rating_snapshots", "organizations"
  add_foreign_key "release_checklists", "organizations"
  add_foreign_key "release_checklists", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "release_notes", "organizations"
  add_foreign_key "release_notes", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "release_notes", "users", column: "reviewed_by_id", on_delete: :nullify
  add_foreign_key "review_response_templates", "organizations"
  add_foreign_key "saved_keyword_ideas", "apple_apps", on_delete: :cascade
  add_foreign_key "saved_keyword_ideas", "users", column: "added_by_user_id", on_delete: :nullify
  add_foreign_key "screenshot_exports", "screenshot_projects"
  add_foreign_key "screenshot_projects", "organizations"
  add_foreign_key "screenshot_scenes", "screenshot_projects"
  add_foreign_key "screenshot_uploads", "organizations"
  add_foreign_key "screenshot_uploads", "screenshot_projects"
  add_foreign_key "sso_configurations", "organizations"
  add_foreign_key "store_listings", "organizations"
  add_foreign_key "testflight_beta_groups", "apple_apps"
  add_foreign_key "testflight_beta_groups", "organizations"
  add_foreign_key "tracked_keyword_countries", "tracked_keywords"
  add_foreign_key "tracked_keywords", "apple_apps"
  add_foreign_key "users", "organizations", column: "last_organization_id"
end
