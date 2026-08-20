class CreateBillingSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :billing_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :provider_subscription_id, null: false
      t.string :provider_plan_id
      t.string :provider_product_id
      t.string :status, null: false, default: "pending"
      t.string :plan_tier, null: false
      t.string :billing_interval, null: false
      t.string :provider_customer_id
      t.string :customer_email
      t.datetime :started_at
      t.datetime :current_period_started_at
      t.datetime :current_period_ends_at
      t.datetime :cancelled_at
      t.datetime :last_synced_at
      t.boolean :cancel_at_period_end, null: false, default: false
      t.jsonb :provider_payload, null: false, default: {}
      t.timestamps
    end

    add_index :billing_subscriptions, [ :provider, :provider_subscription_id ], unique: true, name: "index_billing_subscriptions_on_provider_and_subscription_id"
    add_index :billing_subscriptions, [ :user_id, :created_at ]
    add_index :billing_subscriptions, [ :user_id, :status ]
  end
end
