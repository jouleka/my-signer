class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :organization, optional: true
  belongs_to :resource, polymorphic: true, optional: true

  validates :notification_date, uniqueness: {
    scope: %i[user_id resource_type resource_id notification_type],
    message: "already sent for this resource today"
  }, if: -> { notification_date.present? && resource_type.present? }

  before_validation :set_notification_date, on: :create

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :visible, -> { where(dismissed_at: nil) }

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end

  def dismissed?
    dismissed_at.present?
  end

  def dismiss!
    update!(dismissed_at: Time.current)
  end

  private

  def set_notification_date
    self.notification_date ||= Date.current
  end
end
