class CreateBillingWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :billing_webhook_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :verification_status, null: false, default: "pending"
      t.datetime :processed_at
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    add_index :billing_webhook_events, [ :provider, :event_id ], unique: true, name: "index_billing_webhook_events_on_provider_and_event_id"
    add_index :billing_webhook_events, [ :provider, :event_type ]
  end
end
