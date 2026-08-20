# KMS-backed envelope-encryption accessor for ActiveRecord credential models.
#
# After mysigner-32 (the read-path cutover), the `vaults :foo, kind:` macro is
# the SOLE source of the `foo` and `foo=` accessors on a credential model. Reads
# decrypt from `<attr>_envelope`; writes re-encrypt to the same column on save.
# The AR-encrypted column (e.g. `private_key`) physically remains in the schema
# for one release as a rollback window, but the concern never touches it.
#
# Lifecycle:
#
#   * `record.foo = "x"`
#       Stores "x" in an in-memory map keyed by :foo. Marks :foo dirty so the
#       before_save callback knows to re-encrypt. Does NOT touch any AR column.
#
#   * `record.foo`
#       1. If :foo was set in this object's lifetime, return that value.
#       2. Else if `<attr>_envelope` is nil/blank, return nil.
#       3. Else unpack the envelope, decrypt via CredentialVault with the same
#          {org_id, credential_kind, credential_id} context the writer built,
#          cache the plaintext in the in-memory map, return it.
#
#   * `record.save`
#       before_save :ensure_vault_record_id assigns a UUID in Ruby (so the
#       EncryptionContext has a stable per-record identifier *before* INSERT).
#       before_save :sync_vaulted_envelopes re-encrypts each dirty attr to its
#       envelope column. New records (no envelope yet) always encrypt; for
#       existing rows, the dirty flag gates the KMS round-trip.
#
#   * `record.reload`
#       after_initialize clears the in-memory cache+dirty map so the next
#       getter call goes back to the envelope.
#
# Decrypt failures propagate to the caller. Per ApplicationController's
# rescue_from for CredentialVault::CustomerKeyRevoked / DecryptError, those
# turn into a user-actionable 403 or an internal 500 depending on subclass.
#
# Model requirements:
#   - `vault_record_id`  (uuid, NOT NULL, DB default of gen_random_uuid())
#   - `<attr>_envelope`  (text, nullable) for each `vaults :<attr>, ...`
#   - `organization_id`  (used as the `org_id` context key)
#
# Usage:
#
#   class AppStoreConnectCredential < ApplicationRecord
#     include Vaulted
#
#     vaults :private_key, kind: "asc"   # defines #private_key and #private_key=
#   end
#
# Kind strings are baked into the KMS EncryptionContext of every envelope
# written. They MUST remain stable forever — renaming a kind makes existing
# envelopes undecryptable. Stable values currently in use:
#
#   "asc"                       — AppStoreConnect .p8 key
#   "google_play"               — Google Play service-account JSON
#   "android_keystore"          — .jks file bytes
#   "android_keystore_password" — keystore password
#   "android_key_password"      — key entry password
#   "apple_ads"                 — Apple Search Ads private key PEM
module Vaulted
  extend ActiveSupport::Concern

  included do
    # Per-class registry of vault-managed attributes. Each entry:
    #   attr_name(Symbol) => { kind: String, envelope_column: Symbol }
    class_attribute :vault_attrs, instance_writer: false, default: {}

    before_save :ensure_vault_record_id
    before_save :sync_vaulted_envelopes
    # Snapshot the pending-dirty map into the "saved changes" map so that
    # after_*_commit callbacks can ask `saved_change_to_<attr>?`. Done in
    # after_save (NOT after_commit) because Rails runs after_save BEFORE the
    # commit callbacks, and we need the snapshot in place by then.
    after_save  :snapshot_vaulted_saved_changes
    # after_find fires when a record is materialized from a query (find,
    # where.first, etc.) — exactly the path where we need to discard any
    # leftover in-memory cache from a previous instance.
    #
    # NOTE: we intentionally do NOT hook after_initialize. AR::Core#initialize
    # calls super(attributes) → AM::API#initialize → assign_attributes → our
    # setter (which populates @vaulted_plaintext) → then _run_initialize_callbacks
    # fires LAST. Resetting at after_initialize would wipe out the freshly
    # set in-memory values from `Model.new(attr: value)`. For `Model.new`
    # without args, ivars start unset (Ruby returns nil), and the helpers in
    # this concern lazily `||= {}` them — no callback needed for the new-record
    # path.
    after_find :reset_vaulted_in_memory_state
  end

  # `record.reload` does NOT trigger after_initialize on `self`; it builds a
  # fresh_object internally and copies its @attributes onto self, leaving
  # other ivars alone (see ActiveRecord::Persistence#reload). So reload would
  # otherwise leave @vaulted_plaintext intact and the next read of `private_key`
  # would return the stale in-memory value rather than re-decrypting the (now
  # possibly-changed) envelope. Override here to reset state on every reload.
  def reload(*args)
    reset_vaulted_in_memory_state
    super
  end

  # Raised when the KMS EncryptionContext / AES-GCM AAD would be built with a
  # blank credential identifier. A NULL/blank vault_record_id would weaken the
  # per-record binding that prevents wrapped-DEK swap attacks, so we fail
  # closed rather than emit a context an attacker could more easily collide
  # (L-20).
  class VaultContextError < StandardError; end

  class_methods do
    # The SINGLE source of truth for the KMS EncryptionContext / AES-GCM AAD
    # hash bound to a vaulted credential (L-25). Both the OrgRewrap and the
    # EnvelopeVerifier services previously hand-built this same hash; they now
    # call here so the three copies can never drift. The instance-level
    # `#vault_context` also routes through this method.
    #
    # The context's contents/semantics are UNCHANGED — exactly the three keys
    # {org_id, credential_kind, credential_id} that every existing envelope was
    # written with. Renaming a key or changing a value would orphan every
    # stored envelope, so this method must stay byte-stable forever.
    #
    # @param record [#organization_id, #vault_record_id] the credential row
    # @param kind [String] the stable credential-kind identifier
    # @raise [VaultContextError] if the record's vault_record_id is blank (L-20)
    def context_for(record:, kind:)
      vault_record_id = record.vault_record_id

      # L-20: fail closed if the per-record identifier is missing. Building a
      # context with a NULL credential_id would weaken the swap-attack binding.
      if vault_record_id.blank?
        raise VaultContextError,
          "refusing to build vault context for #{record.class.name}##{record.id || '(new)'}: " \
          "vault_record_id is blank (would weaken the per-record KMS/AAD binding)"
      end

      {
        org_id:          record.organization_id.to_s,
        credential_kind: kind.to_s,
        credential_id:   vault_record_id.to_s
      }
    end

    # Register +attr_name+ as a vault-managed attribute and define its getter
    # and setter on the model class. After this, `record.foo` decrypts from
    # `<attr>_envelope`; `record.foo = "x"` queues an in-memory write that
    # the before_save callback flushes to the envelope column on save.
    #
    # @param attr_name [Symbol] the attribute name; the same name is exposed
    #   as the public accessor.
    # @param kind [String] stable identifier baked into KMS EncryptionContext
    #   (do NOT rename — would orphan all existing envelopes of that kind).
    # @param envelope_column [Symbol] override the default `<attr>_envelope`
    def vaults(attr_name, kind:, envelope_column: nil)
      attr_name       = attr_name.to_sym
      envelope_column = (envelope_column || :"#{attr_name}_envelope").to_sym

      # Merge into a fresh Hash rather than mutating in place — class_attribute
      # propagates by reference, so a mutation here would leak to siblings.
      self.vault_attrs = vault_attrs.merge(
        attr_name => { kind: kind.to_s, envelope_column: envelope_column }
      )

      # Define the accessor methods directly on the model class. Defining on
      # `self` (rather than relying on Concern's instance method definitions)
      # puts them on the class itself, which beats AR's generated attribute
      # methods module — so a plain `column-backed` accessor for `foo` (when
      # the AR column physically exists in the schema, as it still does pre-
      # mysigner-33) is overridden by ours. read_attribute / write_attribute
      # on the AR column are still callable by anyone who really wants them,
      # but the public accessor never goes there.
      define_method(attr_name) do
        read_vaulted_attribute(attr_name)
      end

      define_method(:"#{attr_name}=") do |value|
        write_vaulted_attribute(attr_name, value)
      end

      # Dirty-tracking shims. Models declare cache-invalidation callbacks gated
      # on AR's standard dirty predicates (`<attr>_changed?` for pre-save,
      # `saved_change_to_<attr>?` for after_*_commit). With the AR column no
      # longer being written to, those built-in predicates always return false.
      # Define equivalent predicates backed by the Vaulted in-memory tracker so
      # the existing callbacks keep firing on plaintext changes.
      define_method(:"#{attr_name}_changed?") do
        vaulted_attribute_changed?(attr_name)
      end

      define_method(:"saved_change_to_#{attr_name}?") do
        vaulted_attribute_saved_change?(attr_name)
      end
    end
  end

  private

  def ensure_vault_record_id
    return unless respond_to?(:vault_record_id) && respond_to?(:vault_record_id=)

    self.vault_record_id ||= SecureRandom.uuid
  end

  # Per-attr in-memory caches. Always initialized to fresh hashes so that
  # `record.foo = nil` is distinguishable from "never set" via key presence.
  #
  # `@vaulted_saved_changes` mirrors AR's `saved_changes` map — set in
  # after_save so that after_*_commit callbacks can ask
  # `saved_change_to_<attr>?`. Reset here so a fresh-loaded record reports
  # "no saved change for this attr."
  def reset_vaulted_in_memory_state
    @vaulted_plaintext     = {}
    @vaulted_dirty         = {}
    @vaulted_saved_changes = {}
  end

  def snapshot_vaulted_saved_changes
    # Promote pending dirty flags into "saved changes" (matches AR semantics:
    # `changes` snapshots into `saved_changes` once the save completes).
    # Keep @vaulted_plaintext populated — callers that just saved expect the
    # in-memory value to remain readable without hitting KMS.
    @vaulted_saved_changes = @vaulted_dirty&.dup || {}
    @vaulted_dirty         = {}
  end

  def vaulted_attribute_changed?(attr_name)
    @vaulted_dirty&.key?(attr_name) || false
  end

  def vaulted_attribute_saved_change?(attr_name)
    @vaulted_saved_changes&.key?(attr_name) || false
  end

  def read_vaulted_attribute(attr_name)
    # `key?` distinguishes "was explicitly set to nil" from "never touched".
    # An explicit `record.foo = nil` should return nil without falling
    # through to the envelope decode below.
    if @vaulted_plaintext&.key?(attr_name)
      return @vaulted_plaintext[attr_name]
    end

    config       = self.class.vault_attrs.fetch(attr_name)
    envelope_col = config[:envelope_column]
    packed       = self[envelope_col]
    return nil if packed.blank?

    envelope  = CredentialVault.unpack(packed)
    plaintext = CredentialVault.decrypt(envelope, context: vault_context(config[:kind]))

    # Cache for the lifetime of this object. Reload (via after_initialize)
    # clears this and forces a fresh decrypt.
    @vaulted_plaintext ||= {}
    @vaulted_plaintext[attr_name] = plaintext
    plaintext
  end

  def write_vaulted_attribute(attr_name, value)
    @vaulted_plaintext ||= {}
    @vaulted_dirty     ||= {}

    # Match AR's "no-op write" semantics: assigning the same value (after a
    # round-trip through `to_s`/`strip` etc. in before_validation callbacks)
    # must NOT mark the attribute dirty. Without this guard, a benign call
    # like `before_validation :squish_fields` would re-fire cache-invalidation
    # callbacks gated on `saved_change_to_<attr>?` and KMS-re-encrypt the
    # envelope on every save. read_vaulted_attribute is cheap on the second
    # call (it caches in @vaulted_plaintext after the first decrypt) so the
    # lookup here is at worst one envelope decrypt per save.
    current = read_vaulted_attribute(attr_name) if self.class.vault_attrs.key?(attr_name)

    @vaulted_plaintext[attr_name] = value
    @vaulted_dirty[attr_name]     = true unless value == current
  end

  def sync_vaulted_envelopes
    return if self.class.vault_attrs.empty?

    # No-op when KMS isn't wired up. Lets test/dev environments create
    # credentials without needing a real CMK. Production is gated by the
    # boot check in config/initializers/credential_vault.rb, which raises
    # if MYSIGNER_KMS_KEY_ARN is unset.
    unless CredentialVault.configured?
      # Loud in dev / staging where this is almost always a misconfiguration.
      # Silent in test (so the no-op contract test below doesn't spam logs).
      unless Rails.env.test?
        Rails.logger.warn(
          "[Vaulted] CredentialVault unconfigured — skipping envelope " \
          "write for #{self.class.name}##{id || "(new)"}. " \
          "Set MYSIGNER_KMS_KEY_ARN to enable encryption."
        )
      end
      return
    end

    self.class.vault_attrs.each do |attr_name, config|
      sync_one_vaulted_envelope(attr_name, config)
    end
  end

  def sync_one_vaulted_envelope(attr_name, config)
    envelope_col = config[:envelope_column]
    is_dirty     = @vaulted_dirty&.key?(attr_name)

    # Skip KMS round-trip when (a) the attr wasn't touched in this object's
    # lifetime AND (b) we already have an envelope. New records (no envelope
    # yet) always encrypt; explicit assignments (dirty flag) always re-encrypt.
    return if !is_dirty && self[envelope_col].present?

    plaintext = @vaulted_plaintext&.[](attr_name)

    if plaintext.nil?
      # Treat as "clear" — either explicitly set to nil, or never set on a
      # new record with no envelope yet. The envelope column matches.
      self[envelope_col] = nil
      return
    end

    # BYOK (mysigner-21 sub-ticket 2.3): if the owning org has a customer
    # CMK ARN registered, wrap the DEK under it; otherwise pass nil so
    # CredentialVault falls back to the env-default CMK. The `.presence`
    # collapses "" to nil to match Organization's allow_blank validation.
    key_arn  = organization&.byok_kms_key_arn.presence
    envelope = CredentialVault.encrypt(plaintext.to_s, context: vault_context(config[:kind]), key_arn: key_arn)
    self[envelope_col] = CredentialVault.pack(envelope)
  end

  def vault_context(kind)
    # Delegate to the single shared builder (L-25) so the instance path,
    # OrgRewrap, and EnvelopeVerifier all produce byte-identical contexts.
    # This also enforces the L-20 blank-vault_record_id guard on the
    # read/write path.
    self.class.context_for(record: self, kind: kind)
  end
end
