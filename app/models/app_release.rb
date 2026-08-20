class AppRelease < ApplicationRecord
  belongs_to :organization
  belongs_to :listable, polymorphic: true

  STATUSES = %w[draft in_review live archived].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :listable_type, inclusion: { in: %w[AppleApp AndroidApp] }
  validates :listable_id, uniqueness: {
    scope: [ :organization_id, :listable_type, :version_string ],
    message: "already has a release for this version"
  }, allow_nil: true

  scope :for_app, ->(listable) { where(listable: listable) }
  scope :draft, -> { where(status: "draft") }
  scope :in_review, -> { where(status: "in_review") }
  scope :live, -> { where(status: "live") }
  scope :archived, -> { where(status: "archived") }
  scope :recent, -> { order(updated_at: :desc) }

  def platform
    case listable_type
    when "AppleApp" then :ios
    when "AndroidApp" then :android
    end
  end

  def ios?
    listable_type == "AppleApp"
  end

  def android?
    listable_type == "AndroidApp"
  end

  # Returns all StoreListing records for this app (one per locale).
  def store_listings
    organization.store_listings.where(listable: listable)
  end

  # Returns the StoreListing for a specific locale, or nil.
  def store_listing_for(locale)
    store_listings.find_by(locale: locale)
  end

  # Returns all ReleaseNote records for this app (any version).
  def release_notes
    organization.release_notes.for_app(listable)
  end

  # Returns the ReleaseNote records for THIS specific version.
  def release_notes_for_this_version
    return release_notes.none if version_string.blank?
    release_notes.where(version_string: version_string)
  end

  # Returns the most relevant release note for the primary locale of this version,
  # falling back to any release note for this version, then any unarchived note
  # for the app (newest first).
  def primary_release_note
    notes = release_notes_for_this_version
    return notes.find_by(locale: primary_locale) if notes.exists?(locale: primary_locale)
    return notes.first if notes.exists?
    release_notes.where.not(status: "archived").order(updated_at: :desc).first
  end

  # The "primary" locale for this app, used as the default in the UI.
  # Delegates to the listable model which reads from synced store data:
  # AppleApp uses Apple's primaryLocale; AndroidApp uses Google's default_language.
  def primary_locale
    listable&.primary_locale || "en-US"
  end

  # The current checklist for this app + version, or nil.
  def checklist
    organization.release_checklists.for_app(listable).last
  end

  # The latest synced platform-specific release record (read-only mirror of store data).
  def platform_release
    case listable_type
    when "AppleApp"
      listable.app_store_versions.order(created_at: :desc).first
    when "AndroidApp"
      listable.play_store_releases.order(Arel.sql("COALESCE(released_at, created_at) DESC")).first
    end
  end

  # Computes a unified status from the platform-specific release record.
  # This is display logic, distinct from the local `status` column.
  def computed_status
    pr = platform_release
    return "unknown" unless pr

    case pr
    when AppStoreVersion
      case pr.app_store_state
      when "READY_FOR_SALE", "READY_FOR_DISTRIBUTION" then "live"
      when "IN_REVIEW", "WAITING_FOR_REVIEW", "PENDING_APPLE_RELEASE", "PROCESSING_FOR_DISTRIBUTION", "PENDING_DEVELOPER_RELEASE" then "in_review"
      when "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY" then "rejected"
      else "draft"
      end
    when PlayStoreRelease
      pr.status
    end
  end

  # Display string for the platform release state (e.g., "Ready for Sale", "In Review").
  def computed_status_label
    case computed_status
    when "live" then "Live"
    when "in_review" then "In Review"
    when "rejected" then "Rejected"
    when "draft" then "Draft"
    else "Unknown"
    end
  end
end
