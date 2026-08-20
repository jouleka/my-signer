class AddActionFilterIndexToAuditEvents < ActiveRecord::Migration[8.0]
  def change
    add_index :audit_events,
              [ :organization_id, :action, :created_at ],
              order: { created_at: :desc },
              name: "index_audit_events_on_org_action_created"
  end
end
