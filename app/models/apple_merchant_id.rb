class AppleMerchantId < ApplicationRecord
  belongs_to :organization
  has_many :apple_bundle_id_merchant_ids, dependent: :destroy
  has_many :apple_bundle_ids, through: :apple_bundle_id_merchant_ids

  validates :remote_id, presence: true, uniqueness: { scope: :organization_id }
  validates :identifier, presence: true, uniqueness: { scope: :organization_id }
  validates :identifier, format: { with: /\Amerchant\..+\z/, message: "must start with 'merchant.'" }

  scope :sorted, -> { order(:identifier) }
end
