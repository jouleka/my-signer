class AppleBundleIdMerchantId < ApplicationRecord
  belongs_to :apple_bundle_id
  belongs_to :apple_merchant_id

  validates :apple_bundle_id_id, uniqueness: { scope: :apple_merchant_id_id }
end
