require "rails_helper"

RSpec.describe Billing::Paddle::ProcessWebhookEventJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, plan_tier: :free) }

  around do |example|
    original = ENV.to_hash.slice(
      "BILLING_PROVIDER",
      "PADDLE_ENV",
      "PADDLE_CLIENT_SIDE_TOKEN",
      "PADDLE_API_KEY",
      "PADDLE_WEBHOOK_SECRET",
      "PADDLE_PRO_MONTHLY_PRICE_ID",
      "PADDLE_PRO_YEARLY_PRICE_ID",
      "PADDLE_TEAM_MONTHLY_PRICE_ID",
      "PADDLE_TEAM_YEARLY_PRICE_ID"
    )

    ENV["BILLING_PROVIDER"] = "paddle"
    ENV["PADDLE_ENV"] = "sandbox"
    ENV["PADDLE_CLIENT_SIDE_TOKEN"] = "test_123456789012345678901234567"
    ENV["PADDLE_API_KEY"] = "pdl_sdbx_apikey_123"
    ENV["PADDLE_WEBHOOK_SECRET"] = "whsec_test_secret"
    ENV["PADDLE_PRO_MONTHLY_PRICE_ID"] = "pri_pro_monthly"
    ENV["PADDLE_PRO_YEARLY_PRICE_ID"] = "pri_pro_yearly"
    ENV["PADDLE_TEAM_MONTHLY_PRICE_ID"] = "pri_team_monthly"
    ENV["PADDLE_TEAM_YEARLY_PRICE_ID"] = "pri_team_yearly"

    example.run
  ensure
    clear_enqueued_jobs
    clear_performed_jobs
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  it "processes a real subscription webhook and marks it processed" do
    event = BillingWebhookEvent.create!(
      provider: "paddle",
      event_id: "evt_job_real_123",
      event_type: "subscription.updated",
      verification_status: "verified",
      payload: {
        "event_id" => "evt_job_real_123",
        "event_type" => "subscription.updated",
        "occurred_at" => "2026-03-25T10:00:00Z",
        "data" => {
          "id" => "sub_job_real_123",
          "status" => "active",
          "customer_id" => "ctm_job_real_123",
          "items" => [ { "price" => { "id" => "pri_team_yearly" } } ],
          "custom_data" => { "user_id" => user.id },
          "current_billing_period" => {
            "starts_at" => "2026-03-25T10:00:00Z",
            "ends_at" => "2027-03-25T10:00:00Z"
          },
          "created_at" => "2026-03-25T10:00:00Z"
        }
      }
    )

    described_class.perform_now(event.id)

    expect(user.reload.plan_tier).to eq("team")
    expect(event.reload.processed_at).to be_present
    expect(BillingSubscription.find_by(provider_subscription_id: "sub_job_real_123")&.status).to eq("active")
  end

  it "marks unmappable simulated subscription payloads processed without creating a local subscription" do
    event = BillingWebhookEvent.create!(
      provider: "paddle",
      event_id: "evt_job_sim_subscription",
      event_type: "subscription.created",
      verification_status: "verified",
      payload: {
        "event_id" => "evt_job_sim_subscription",
        "event_type" => "subscription.created",
        "occurred_at" => "2026-03-25T10:00:00Z",
        "data" => {
          "id" => "sub_job_sim_123",
          "status" => "active",
          "customer_id" => "ctm_job_sim_123",
          "items" => [ { "price" => { "id" => "pri_sim_unknown" } } ],
          "custom_data" => nil,
          "created_at" => "2026-03-25T10:00:00Z"
        }
      }
    )

    expect { described_class.perform_now(event.id) }.not_to raise_error

    expect(event.reload.processed_at).to be_present
    expect(BillingSubscription.find_by(provider_subscription_id: "sub_job_sim_123")).to be_nil
  end

  it "marks simulated transaction payloads processed when the linked subscription cannot be fetched" do
    client = instance_double(Billing::Paddle::Client)
    allow(Billing::Paddle::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_subscription).with("sub_job_missing").and_raise(
      Billing::Paddle::Client::NotFoundError.new("Entity not found", status: 404)
    )

    event = BillingWebhookEvent.create!(
      provider: "paddle",
      event_id: "evt_job_sim_transaction_missing",
      event_type: "transaction.completed",
      verification_status: "verified",
      payload: {
        "event_id" => "evt_job_sim_transaction_missing",
        "event_type" => "transaction.completed",
        "occurred_at" => "2026-03-25T10:05:00Z",
        "data" => {
          "id" => "txn_job_missing",
          "subscription_id" => "sub_job_missing"
        }
      }
    )

    expect { described_class.perform_now(event.id) }.not_to raise_error

    expect(event.reload.processed_at).to be_present
  end

  it "keeps the webhook pending when an unexpected retryable error occurs" do
    client = instance_double(Billing::Paddle::Client)
    allow(Billing::Paddle::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_subscription).with("sub_retry_job").and_raise(StandardError, "temporary outage")

    event = BillingWebhookEvent.create!(
      provider: "paddle",
      event_id: "evt_job_retry",
      event_type: "transaction.updated",
      verification_status: "verified",
      payload: {
        "event_id" => "evt_job_retry",
        "event_type" => "transaction.updated",
        "occurred_at" => "2026-03-25T10:06:00Z",
        "data" => {
          "id" => "txn_job_retry",
          "subscription_id" => "sub_retry_job"
        }
      }
    )

    expect {
      described_class.perform_now(event.id)
    }.to have_enqueued_job(described_class).with(event.id)

    expect(event.reload.processed_at).to be_nil
  end
end
