class AppleBuild < ApplicationRecord
  belongs_to :organization
  belongs_to :apple_app
  has_one :app_store_version, dependent: :nullify

  validates :build_id, presence: true, uniqueness: true
  validates :version, presence: true
  validates :build_number, presence: true

  scope :by_version_and_build, ->(version, build_number) { where(version: version, build_number: build_number) }
  scope :processed, -> { where(processing_state: [ "VALID", "PROCESSING_COMPLETE" ]) }
end
