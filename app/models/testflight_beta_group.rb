class TestflightBetaGroup < ApplicationRecord
  belongs_to :organization
  belongs_to :apple_app

  validates :remote_id, presence: true, uniqueness: { scope: :organization_id }

  scope :internal, -> { where(is_internal_group: true) }
  scope :external, -> { where(is_internal_group: false) }
  scope :publicly_joinable, -> { where(public_link_enabled: true) }
end
