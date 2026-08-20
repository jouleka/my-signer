# Adds the per-org BYOK CMK ARN column to organizations.
#
# When set, the CredentialVault wraps DEKs for this org's credentials with the
# customer's CMK (in their AWS account) instead of MySigner's env-default CMK.
# Nullable: NULL means "use env default" (the Epic 1 behavior).
#
# No index — read pattern is "row already loaded, decide which CMK ARN to pass
# into CredentialVault.encrypt". No lookups by ARN.
#
# Companion ticket: mysigner-21.
class AddByokKmsKeyArnToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :byok_kms_key_arn, :text, null: true
  end
end
