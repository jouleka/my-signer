class CustomProductPageVersion < ApplicationRecord
  belongs_to :custom_product_page
  belongs_to :organization

  has_many :custom_product_page_localizations, dependent: :destroy

  validates :remote_id, presence: true, uniqueness: true
  validates :state, presence: true

  STATES = %w[PREPARE_FOR_SUBMISSION WAITING_FOR_REVIEW IN_REVIEW APPROVED PUBLISHED REJECTED].freeze
  validates :state, inclusion: { in: STATES }

  SUBMISSION_STATUSES = %w[submitted failed].freeze

  def draft?
    state == "PREPARE_FOR_SUBMISSION"
  end

  def published?
    state == "PUBLISHED"
  end

  def submittable?
    draft? && submission_status != "submitted"
  end
end
