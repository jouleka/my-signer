class AndroidBuild < ApplicationRecord
  belongs_to :organization
  belongs_to :android_app
  has_many :android_tracks, through: :android_app

  validates :version_code, presence: true, uniqueness: { scope: :android_app_id }

  scope :recent, -> { order(Arel.sql("COALESCE(uploaded_at, created_at) DESC")) }
  scope :by_version, ->(version_code) { where(version_code: version_code) }
  scope :uploaded_after, lambda { |timestamp|
    timestamp.present? ? where("COALESCE(uploaded_at, created_at) >= ?", timestamp) : all
  }

  def display_version
    return version_code if version_name.blank?

    "#{version_name} (#{version_code})"
  end
end
