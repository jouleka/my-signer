class CreateAuditEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_events do |t|
      t.references :organization, null: false, foreign_key: true, index: true
      t.references :actor, foreign_key: { to_table: :users }, null: true, index: true
      t.string  :action,          null: false
      t.string  :resource_type
      t.bigint  :resource_id
      t.jsonb   :metadata,        null: false, default: {}
      t.string  :ip_address
      t.string  :user_agent

      # Immutability: no updated_at. Audit events are append-only.
      t.datetime :created_at,     null: false
    end

    # Primary query pattern: all events for an org, newest first.
    add_index :audit_events, [ :organization_id, :created_at ], order: { created_at: :desc }
    add_index :audit_events, :action
    add_index :audit_events, [ :resource_type, :resource_id ]
  end
end
