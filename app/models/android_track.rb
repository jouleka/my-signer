class AndroidTrack < ApplicationRecord
  belongs_to :android_app

  TRACKS = %w[internal alpha beta production].freeze

  before_validation :squish_fields

  validates :track_name, presence: true, inclusion: { in: TRACKS }
  validates :track_name, uniqueness: { scope: :android_app_id }

  private

  def squish_fields
    self.track_name = track_name.to_s.strip
    self.status = status.to_s.strip
  end
end
