class TrialHistory < ApplicationRecord
  validates :email_hash, presence: true, uniqueness: true
  validates :started_at, presence: true

  # We HMAC the normalized email with `Rails.application.secret_key_base`
  # rather than using a plain SHA-256 digest. The secret_key_base is stable
  # for the lifetime of the app -- rotating it would break Devise's
  # encrypted columns and existing sessions, so it's effectively forever.
  # Using HMAC with this key prevents an attacker who steals just the
  # `trial_histories` table from enumerating common emails via rainbow
  # tables: without the key they cannot recompute the digest for a
  # candidate email.
  HASH_ALGORITHM = "SHA256".freeze

  # Deterministic hash for a given email. The email is normalized first so
  # common input variations resolve to the same hash:
  # - whitespace stripped, case lowered
  # - the "+tag" subaddress (everything between the first "+" and the "@")
  #   is stripped, so "user+trial2@acme.com" and "user@acme.com" collide.
  #   This blocks the "delete account, re-register with `email+1`" trial
  #   loop.
  # - for Gmail, dots in the local part are insignificant
  #   ("j.smith@gmail.com" == "jsmith@gmail.com"), and googlemail.com is the
  #   same mailbox as gmail.com. Both are folded to the canonical form.
  # Returns nil for malformed input (no "@", empty local/domain).
  def self.hash_for(email)
    normalized = normalize(email)
    return nil if normalized.nil?

    OpenSSL::HMAC.hexdigest(HASH_ALGORITHM, Rails.application.secret_key_base, normalized)
  end

  # Gmail treats these two domains as the same mailbox, and strips dots from
  # the local part. Apply the same collapse here so the trial guard catches
  # `j.smith@googlemail.com` re-entering as `jsmith@gmail.com`.
  GMAIL_ALIASED_DOMAINS = %w[gmail.com googlemail.com].freeze

  # Strip whitespace, lowercase, then drop any "+tag" subaddress before "@".
  # For Gmail addresses, additionally fold googlemail.com -> gmail.com and
  # remove dots from the local part.
  # Example: "User+Trial2@Acme.COM" -> "user@acme.com"
  # Example: "J.Smith+promo@googlemail.com" -> "jsmith@gmail.com"
  # Returns nil for malformed input (no "@", or empty local/domain).
  def self.normalize(email)
    local, domain = email.to_s.downcase.strip.split("@", 2)
    return nil if local.blank? || domain.blank?

    local_no_tag = local.split("+", 2).first
    return nil if local_no_tag.blank?

    if GMAIL_ALIASED_DOMAINS.include?(domain)
      local_no_tag = local_no_tag.delete(".")
      return nil if local_no_tag.blank?
      domain = "gmail.com"
    end

    "#{local_no_tag}@#{domain}"
  end

  def self.claimed?(email)
    hash = hash_for(email)
    return false if hash.nil?

    exists?(email_hash: hash)
  end

  # Records a trial claim for the given email. Idempotent: if the email is
  # already recorded, returns the existing record without creating a new one.
  # Uses `upsert` semantics to handle concurrent claims without spinning.
  # Returns nil for malformed emails (cannot be hashed).
  def self.claim!(email)
    hash = hash_for(email)
    return nil if hash.nil?

    record = find_by(email_hash: hash)
    return record if record

    create!(email_hash: hash, started_at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    # Another transaction beat us to it -- re-fetch and return.
    find_by(email_hash: hash)
  end
end
