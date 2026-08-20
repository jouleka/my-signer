class AllowNullOrganizationOnAuditEvents < ActiveRecord::Migration[8.0]
  # Lets an audit event outlive the organization it referenced so the
  # `organization_deleted` event is recordable and the pre-deletion audit
  # history survives for compliance review.
  #
  # Previously: audit_events.organization_id was NOT NULL with a plain FK
  # (NO ACTION). Organization destroy relied on `dependent: :delete_all` to
  # clear the referencing rows before deleting the org row, which meant the
  # `organization_deleted` audit log -- written after destroy returned --
  # hit an FK violation and was silently swallowed by Audit::Logger.
  def up
    change_column_null :audit_events, :organization_id, true

    remove_foreign_key :audit_events, :organizations
    add_foreign_key :audit_events, :organizations, on_delete: :nullify
  end

  def down
    # Reverting is destructive: orphan events (organization_id IS NULL) must
    # be cleared first or the NOT NULL constraint would fail to re-apply.
    execute "DELETE FROM audit_events WHERE organization_id IS NULL"

    remove_foreign_key :audit_events, :organizations
    add_foreign_key :audit_events, :organizations
    change_column_null :audit_events, :organization_id, false
  end
end
