class AppleBundleIdAppGroup < ApplicationRecord
  belongs_to :apple_bundle_id
  belongs_to :apple_app_group

  validates :apple_bundle_id_id, uniqueness: { scope: :apple_app_group_id }
end
