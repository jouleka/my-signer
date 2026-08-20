class TrackedKeywordCountry < ApplicationRecord
  belongs_to :tracked_keyword
  # Nullify on destroy — preserves historical ranking rows so users don't lose
  # paid-for history when they untrack a keyword. The Retention job (respects
  # per-tier max_keyword_history_days) eventually cleans rows up by checked_on.
  has_many :keyword_rankings, dependent: :nullify
  has_one :apple_app, through: :tracked_keyword
  has_one :organization, through: :apple_app

  validates :country, presence: true, inclusion: { in: Aso::Countries::SUPPORTED },
                      uniqueness: { scope: :tracked_keyword_id }
  validates :current_rank, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: 250
  }, allow_nil: true
end
