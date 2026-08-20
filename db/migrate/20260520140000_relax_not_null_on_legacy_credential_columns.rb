# Companion to mysigner-32 (credential read-path cutover).
#
# After the cutover, the Vaulted concern reads AND writes credential plaintext
# exclusively through `<attr>_envelope` columns. The legacy Rails-AR-encrypted
# columns (e.g. `private_key`, `service_account_json`, `keystore_file` etc.)
# remain physically in the schema for one release as a rollback window, but
# the application no longer writes to them.
#
# All but one of those columns are already nullable. The exception is
# `android_keystores.keystore_file`, which was defined with `null: false` —
# back when the AR setter populated it on every INSERT. Without this
# migration the cutover would crash every keystore INSERT with a
# NotNullViolation.
#
# This migration ONLY relaxes the constraint. The column itself stays; the
# follow-up mysigner-33 drops the legacy columns wholesale.
class RelaxNotNullOnLegacyCredentialColumns < ActiveRecord::Migration[8.0]
  def up
    change_column_null :android_keystores, :keystore_file, true
  end

  def down
    # Reverting requires the legacy column to have a value on every row.
    # Post-cutover, new rows ship with NULL in this column (we no longer
    # write to it). A naive `change_column_null false` here would fail on
    # any row inserted after the cutover went live. Operators rolling back
    # must first re-populate the column (out of scope for this migration).
    raise ActiveRecord::IrreversibleMigration,
          "Cannot re-add NOT NULL — rows inserted after mysigner-32 have NULL " \
          "in android_keystores.keystore_file. Backfill the column first."
  end
end
