class KeywordRanking < ApplicationRecord
  # Phase C dropped the legacy polymorphic columns (`listable_type`,
  # `listable_id`, `locale`). `tracked_keyword_country_id` stays NULLABLE
  # so TrackedKeywordCountry#destroy can nullify it (dependent: :nullify) —
  # preserving paid-for rank history when a user untracks a keyword. Live
  # rankings reach their owning app through the FK chain
  # tracked_keyword_country -> tracked_keyword -> apple_app; orphaned rows
  # (FK = nil) remain queryable via `organization_id` + `keyword` until the
  # Retention job prunes them by `checked_on`.
  belongs_to :organization
  belongs_to :tracked_keyword_country, optional: true

  validates :keyword, presence: true
  validates :checked_on, presence: true
  validates :keyword, uniqueness: { scope: [ :tracked_keyword_country_id, :checked_on ] }
  validates :rank, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 250 }, allow_nil: true

  # Scopes keyed off the TrackedKeywordCountry FK chain. `for_app` used to
  # accept any polymorphic listable, but every surviving ranking belongs to
  # an AppleApp via TrackedKeyword; the scope now joins explicitly.
  scope :for_app, ->(apple_app) {
    joins(tracked_keyword_country: :tracked_keyword)
      .where(tracked_keywords: { apple_app_id: apple_app.is_a?(AppleApp) ? apple_app.id : apple_app })
  }
  scope :for_keyword, ->(kw) { where(keyword: kw) }
  scope :recent, ->(days = 30) { where(checked_on: days.days.ago.to_date..) }
  scope :ranked, -> { where.not(rank: nil) }
  scope :ordered, -> { order(checked_on: :desc) }
end
