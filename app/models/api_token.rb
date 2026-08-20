class ApiToken < ApplicationRecord
  belongs_to :organization
  belongs_to :user

  # Scopes: read, write, admin
  VALID_SCOPES = %w[read write admin].freeze

  validates :name, presence: true, length: { maximum: 100 }
  validates :token_digest, presence: true, uniqueness: true
  validates :organization, presence: true
  validates :user, presence: true
  validate :validate_scopes

  scope :active, -> { where(revoked: false).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :revoked, -> { where(revoked: true) }
  scope :for_organization, ->(org_id) { where(organization_id: org_id) }

  # Generate a new token and return the plain text version (only shown once)
  def self.generate_for(user:, organization:, name:, scopes: [ "read" ], expires_in: nil)
    plain_token = SecureRandom.urlsafe_base64(32)
    digest = Digest::SHA256.hexdigest(plain_token)

    token = create!(
      user: user,
      organization: organization,
      name: name,
      token_digest: digest,
      scopes: Array(scopes).join(","),
      expires_at: expires_in ? expires_in.from_now : nil
    )

    # Return both the record and the plain token (only time it's available)
    [ token, plain_token ]
  end

  # Find token by plain text token
  def self.find_by_token(plain_token)
    return nil if plain_token.blank?
    digest = Digest::SHA256.hexdigest(plain_token)
    active.find_by(token_digest: digest)
  end

  # Check if token has a specific scope
  def has_scope?(scope)
    return true if scopes_array.include?("admin") # Admin has all scopes
    scopes_array.include?(scope.to_s)
  end

  def scopes_array
    (scopes || "read").split(",").map(&:strip)
  end

  def revoke!
    update!(revoked: true, revoked_at: Time.current)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    !revoked? && !expired?
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  def masked_token
    "#{name} (created #{created_at.to_date})"
  end

  private

  def validate_scopes
    return if scopes.blank?
    invalid = scopes_array - VALID_SCOPES
    errors.add(:scopes, "contains invalid scopes: #{invalid.join(', ')}") if invalid.any?
  end
end
