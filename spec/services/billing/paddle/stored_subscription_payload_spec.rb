require "rails_helper"

RSpec.describe Billing::Paddle::StoredSubscriptionPayload do
  it "keeps only entitlement metadata and drops customer data" do
    payload = {
      "customer_id" => "customer-123",
      "custom_data" => { "customer_email" => "person@example.test", "token" => "do-not-store" },
      "current_billing_period" => { "starts_at" => "2026-08-01", "ends_at" => "2026-09-01" },
      "scheduled_change" => {
        "action" => "update",
        "effective_at" => "2026-09-01T00:00:00Z",
        "items" => [ { "price" => { "id" => "price-team", "description" => "unused" } } ]
      }
    }

    stored = described_class.build(payload, event_occurred_at: "2026-08-20T10:00:00Z")

    expect(stored).to eq(
      "scheduled_change" => {
        "action" => "update",
        "effective_at" => "2026-09-01T00:00:00Z",
        "items" => [ { "price" => { "id" => "price-team" } } ]
      },
      "last_event_occurred_at" => "2026-08-20T10:00:00Z"
    )
    expect(stored.to_json).not_to include("customer", "person@example.test", "do-not-store")
  end
end
