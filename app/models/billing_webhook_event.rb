class BillingWebhookEvent < ApplicationRecord
  enum :verification_status, {
    pending: "pending",
    verified: "verified",
    invalid: "invalid"
  }, prefix: true

  validates :provider, presence: true
  validates :event_id, presence: true, uniqueness: { scope: :provider }
  validates :event_type, presence: true
  validates :verification_status, presence: true
end
