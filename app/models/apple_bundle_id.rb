class AppleBundleId < ApplicationRecord
  belongs_to :organization
  has_many :apple_bundle_id_capabilities, dependent: :destroy
  has_many :apple_bundle_id_merchant_ids, dependent: :destroy
  has_many :apple_merchant_ids, through: :apple_bundle_id_merchant_ids
  has_many :apple_bundle_id_app_groups, dependent: :destroy
  has_many :apple_app_groups, through: :apple_bundle_id_app_groups

  scope :sorted, -> { order(:identifier) }

  def capabilities_count
    apple_bundle_id_capabilities.count
  end

  def platform_icon
    case platform
    when "IOS" then "fa-mobile-screen"
    when "MAC_OS" then "fa-laptop"
    when "UNIVERSAL" then "fa-layer-group"
    else "fa-cube"
    end
  end
end
