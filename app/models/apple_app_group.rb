class AppleAppGroup < ApplicationRecord
  belongs_to :organization
  has_many :apple_bundle_id_app_groups, dependent: :destroy
  has_many :apple_bundle_ids, through: :apple_bundle_id_app_groups

  validates :identifier, presence: true, uniqueness: { scope: :organization_id }
  validates :identifier, format: { with: /\Agroup\..+\z/, message: "must start with 'group.'" }

  scope :sorted, -> { order(:identifier) }
end
