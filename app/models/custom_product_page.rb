class CustomProductPage < ApplicationRecord
  belongs_to :organization
  belongs_to :apple_app

  has_many :custom_product_page_versions, dependent: :destroy
  has_many :custom_product_page_localizations, through: :custom_product_page_versions

  validates :remote_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :visible, -> { where(visible: true) }
  scope :for_app, ->(app) { where(apple_app: app) }
  scope :ordered, -> { order(created_at: :desc) }

  def published_version
    custom_product_page_versions.find_by(state: "PUBLISHED")
  end

  def draft_version
    custom_product_page_versions.find_by(state: "PREPARE_FOR_SUBMISSION")
  end

  def latest_version
    custom_product_page_versions.order(created_at: :desc).first
  end

  def performance_impressions
    performance_data.dig("impressions").to_i
  end

  def performance_downloads
    performance_data.dig("downloads").to_i
  end

  def performance_conversion_rate
    performance_data.dig("conversion_rate").to_f
  end

  def performance_available?
    performance_data.present? && performance_data.keys.any?
  end
end
