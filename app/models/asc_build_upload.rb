class AscBuildUpload < ApplicationRecord
  STATES = %w[pending uploaded failed abandoned].freeze

  belongs_to :organization
  belongs_to :apple_app
  # `optional: true` so a row outlives the FK-nullify cascade fired by
  # PendingDeletionPurgeJob when the original uploader is hard-deleted
  # 90 days after their self-initiated soft-delete. The upload row itself
  # belongs to the org (which still exists), and the org's surviving
  # admins keep their record of the release event with the author shown
  # as nil. See db/migrate/20260507120000_nullify_asc_build_uploads_user_on_user_delete.
  belongs_to :user, optional: true

  validates :remote_id, :remote_file_id, :cf_bundle_version, :cf_bundle_short_version_string,
            :platform, :file_name, :file_size, :state, presence: true
  validates :state, inclusion: { in: STATES }
  validates :file_size, numericality: { greater_than: 0 }

  scope :pending,    -> { where(state: "pending") }
  scope :uploaded,   -> { where(state: "uploaded") }
  scope :failed,     -> { where(state: "failed") }
  scope :abandoned,  -> { where(state: "abandoned") }
  scope :terminal,   -> { where(state: %w[uploaded failed abandoned]) }

  def terminal?
    %w[uploaded failed abandoned].include?(state)
  end
end
