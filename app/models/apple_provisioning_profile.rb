class AppleProvisioningProfile < ApplicationRecord
  belongs_to :organization

  scope :expiring_within, lambda { |days|
    return none if days.to_i <= 0
    where.not(expires_at: nil).where("expires_at <= ?", days.to_i.days.from_now.end_of_day)
  }
end
