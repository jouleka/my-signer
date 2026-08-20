require "rails_helper"
require "openssl"

RSpec.describe "Billing Paddle", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user, plan_tier: :free) }
  let(:organization) { create(:organization, owner: user) }

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

  describe "POST /billing/paddle/checkout_complete" do
    before do
      sign_in user, scope: :user
      post switch_organization_path(organization)
    end

    it "synchronizes the user plan from the completed Paddle transaction" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_transaction).with("txn_123").and_return(
        "id" => "txn_123",
        "status" => "completed",
        "subscription_id" => "sub_123",
        "updated_at" => "2026-03-25T10:00:00Z"
      )
      allow(client).to receive(:get_subscription).with("sub_123").and_return(
        "id" => "sub_123",
        "status" => "active",
        "customer_id" => "ctm_123",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ],
        "custom_data" => { "user_id" => user.id },
        "current_billing_period" => {
          "starts_at" => "2026-03-25T10:00:00Z",
          "ends_at" => "2026-04-25T10:00:00Z"
        },
        "created_at" => "2026-03-25T10:00:00Z"
      )

      post billing_paddle_checkout_complete_path, params: {
        transaction_id: "txn_123",
        return_to: pricing_path
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true, "activated" => true, "redirect_url" => pricing_path)
      expect(user.reload.plan_tier).to eq("pro")
      expect(BillingSubscription.find_by(provider_subscription_id: "sub_123")&.provider_customer_id).to eq("ctm_123")
    end

    it "returns a retry hint when checkout completed before the transaction is fully completed" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_transaction).with("txn_pending_123").and_return(
        "id" => "txn_pending_123",
        "status" => "paid",
        "updated_at" => "2026-03-25T10:00:00Z"
      )

      post billing_paddle_checkout_complete_path, params: {
        transaction_id: "txn_pending_123",
        return_to: pricing_path
      }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to include(
        "ok" => true,
        "activated" => false,
        "redirect_url" => pricing_path,
        "retry_after_ms" => 1200
      )
    end

    it "does not activate a new checkout while Paddle still shows the transaction as pending capture" do
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_existing_123",
        provider_customer_id: "ctm_existing_123",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )
      user.update!(plan_tier: :pro)

      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_transaction).with("txn_capture_pending_123").and_return(
        "id" => "txn_capture_pending_123",
        "status" => "paid",
        "subscription_id" => "sub_team_pending_123",
        "custom_data" => { "user_id" => user.id },
        "updated_at" => "2026-03-25T10:00:00Z"
      )
      expect(client).not_to receive(:get_subscription)

      post billing_paddle_checkout_complete_path, params: {
        transaction_id: "txn_capture_pending_123",
        return_to: pricing_path
      }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to include("ok" => true, "activated" => false, "redirect_url" => pricing_path)
      expect(user.reload.plan_tier).to eq("pro")
      expect(BillingSubscription.find_by(provider_subscription_id: "sub_team_pending_123")).to be_nil
    end

    it "rejects checkout completion when the Paddle subscription belongs to a different user" do
      other_user = create(:user, plan_tier: :free)
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_transaction).with("txn_wrong_owner_123").and_return(
        "id" => "txn_wrong_owner_123",
        "status" => "completed",
        "subscription_id" => "sub_wrong_owner_123",
        "updated_at" => "2026-03-25T10:00:00Z"
      )
      allow(client).to receive(:get_subscription).with("sub_wrong_owner_123").and_return(
        "id" => "sub_wrong_owner_123",
        "status" => "active",
        "customer_id" => "ctm_wrong_owner_123",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ],
        "custom_data" => { "user_id" => other_user.id },
        "current_billing_period" => {
          "starts_at" => "2026-03-25T10:00:00Z",
          "ends_at" => "2026-04-25T10:00:00Z"
        }
      )

      post billing_paddle_checkout_complete_path, params: {
        transaction_id: "txn_wrong_owner_123",
        return_to: pricing_path
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("ok" => false, "error" => "Unable to confirm Paddle checkout yet.")
      expect(user.reload.plan_tier).to eq("free")
      expect(BillingSubscription.find_by(provider_subscription_id: "sub_wrong_owner_123")).to be_nil
    end
  end

  describe "POST /billing/paddle/portal_session" do
    before do
      sign_in user, scope: :user
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_123",
        provider_customer_id: "ctm_123",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )
    end

    it "redirects signed-in users to a Paddle customer portal session" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:create_customer_portal_session).with("ctm_123").and_return(
        "urls" => {
          "general" => {
            "overview" => "https://billing.example.test/session"
          }
        }
      )

      post billing_paddle_portal_session_path

      expect(response).to redirect_to("https://billing.example.test/session")
    end

    it "rejects non-Paddle subscriptions" do
      BillingSubscription.delete_all
      BillingSubscription.create!(
        user: user,
        provider: "legacy",
        provider_subscription_id: "sub_legacy_123",
        provider_customer_id: "ctm_legacy_123",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )

      post billing_paddle_portal_session_path

      expect(response).to redirect_to(pricing_path)
      follow_redirect!
      expect(response.body).to include("This subscription cannot be managed online yet.")
    end

    it "handles missing portal overview URLs" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:create_customer_portal_session).with("ctm_123").and_return(
        "urls" => { "general" => {} }
      )

      post billing_paddle_portal_session_path

      expect(response).to redirect_to(pricing_path)
      follow_redirect!
      expect(response.body).to include("Billing management is temporarily unavailable.")
    end

    it "opens the subscription cancellation flow when requested" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_123").and_return(
        "id" => "sub_123",
        "management_urls" => {
          "cancel" => "https://billing.example.test/cancel"
        }
      )

      post billing_paddle_portal_session_path, params: { purpose: "cancel" }

      expect(response).to redirect_to("https://billing.example.test/cancel")
    end
  end

  describe "POST /billing/paddle/subscription_change_preview" do
    before do
      sign_in user, scope: :user
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_preview_123",
        provider_customer_id: "ctm_preview_123",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly",
        current_period_ends_at: 1.month.from_now
      )
    end

    it "returns a normalized billing preview for supported changes" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_preview_123").and_return(
        "id" => "sub_preview_123",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" }, "quantity" => 1 } ],
        "next_billed_at" => 1.month.from_now.iso8601
      )
      allow(client).to receive(:preview_subscription_update).and_return(
        "immediate_transaction" => {
          "details" => { "totals" => { "total" => "0", "currency_code" => "USD" } }
        },
        "next_transaction" => {
          "details" => { "totals" => { "total" => "9600", "currency_code" => "USD" } },
          "billing_period" => { "starts_at" => 1.month.from_now.iso8601 }
        },
        "recurring_transaction_details" => {
          "totals" => { "total" => "9600", "currency_code" => "USD" }
        },
        "update_summary" => {
          "result" => { "action" => "credit", "amount" => "1200", "currency_code" => "USD" }
        }
      )

      post billing_paddle_subscription_change_preview_path, params: {
        plan_tier: "pro",
        billing_interval: "yearly"
      }, as: :json

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      expect(payload["ok"]).to eq(true)
      expect(payload.dig("preview", "title")).to eq("Pro Yearly")
      expect(payload.dig("preview", "due_today", "amount_cents")).to eq(0)
      expect(payload.dig("preview", "next_charge", "formatted_amount")).to eq("$96")
      expect(payload.dig("preview", "recurring_charge", "formatted_amount")).to eq("$96")
      expect(payload.dig("preview", "summary_line")).to include("prorated credit")
    end
  end

  describe "POST /billing/paddle/subscription_change" do
    before do
      sign_in user, scope: :user
    end

    it "applies immediate pro to team upgrades" do
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_change_123",
        provider_customer_id: "ctm_change_123",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly",
        current_period_ends_at: 2.weeks.from_now
      )
      user.update!(plan_tier: :pro)

      client = instance_double(Billing::Paddle::Client)
      synchronizer = instance_double(Billing::Paddle::Synchronizer)
      synced_subscription = BillingSubscription.new(plan_tier: "team", billing_interval: "monthly", status: "active")

      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(Billing::Paddle::Synchronizer).to receive(:new).and_return(synchronizer)
      allow(client).to receive(:get_subscription).with("sub_change_123").and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" }, "quantity" => 1 } ],
        "next_billed_at" => 2.weeks.from_now.iso8601
      )
      allow(client).to receive(:preview_subscription_update).and_return({ "update_summary" => {} })
      allow(client).to receive(:update_subscription).and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "updated_at" => Time.current.iso8601,
        "customer_id" => "ctm_change_123",
        "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
        "custom_data" => { "user_id" => user.id },
        "current_billing_period" => {
          "starts_at" => Time.current.iso8601,
          "ends_at" => 1.month.from_now.iso8601
        }
      )
      allow(synchronizer).to receive(:synchronize_subscription_payload!).and_return(synced_subscription)

      post billing_paddle_subscription_change_path, params: {
        plan_tier: "team",
        billing_interval: "monthly",
        return_to: pricing_path
      }

      expect(response).to redirect_to(pricing_path)
      expect(flash[:notice]).to eq("Team plan is active.")
    end

    it "schedules team to pro downgrades and surfaces blocked-organization warnings" do
      user.update!(plan_tier: :team)
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_downgrade_123",
        provider_customer_id: "ctm_downgrade_123",
        provider_plan_id: "pri_team_monthly",
        status: "active",
        plan_tier: "team",
        billing_interval: "monthly",
        current_period_ends_at: 1.month.from_now
      )
      5.times { |n| create(:organization, owner: user, name: "Downgrade Org #{n + 1}", created_at: (5 - n).days.ago) }

      client = instance_double(Billing::Paddle::Client)
      synchronizer = instance_double(Billing::Paddle::Synchronizer)

      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(Billing::Paddle::Synchronizer).to receive(:new).and_return(synchronizer)
      allow(client).to receive(:get_subscription).with("sub_downgrade_123").and_return(
        "id" => "sub_downgrade_123",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_team_monthly" }, "quantity" => 1 } ],
        "next_billed_at" => 1.month.from_now.iso8601
      )
      allow(client).to receive(:preview_subscription_update).and_return({ "update_summary" => {} })
      allow(client).to receive(:update_subscription).and_return(
        "id" => "sub_downgrade_123",
        "status" => "active",
        "updated_at" => Time.current.iso8601,
        "customer_id" => "ctm_downgrade_123",
        "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
        "scheduled_change" => {
          "effective_at" => 1.month.from_now.iso8601,
          "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ]
        },
        "current_billing_period" => {
          "starts_at" => Time.current.iso8601,
          "ends_at" => 1.month.from_now.iso8601
        }
      )
      allow(synchronizer).to receive(:synchronize_subscription_payload!)

      post billing_paddle_subscription_change_path, params: {
        plan_tier: "pro",
        billing_interval: "monthly",
        return_to: pricing_path
      }

      expect(response).to redirect_to(pricing_path)
      expect(flash[:notice]).to include("Pro Monthly is scheduled")
      expect(flash[:notice]).to include("will be blocked")
      expect(BillingSubscription.find_by!(provider_subscription_id: "sub_downgrade_123").scheduled_change_price_id).to eq("pri_pro_monthly")
    end
  end

  describe "GET /settings" do
    before do
      sign_in user, scope: :user
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_settings_123",
        provider_customer_id: "ctm_settings_123",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )
    end

    it "renders the billing management CTA for active subscriptions" do
      get settings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Invoices & billing")
      expect(response.body).to include("Cancel")
    end

    it "renders persistent plan overage warnings for the current organization" do
      organization = create(:organization, owner: user, name: "Overflow Settings Org")
      user.update!(plan_tier: :pro)
      create(:screenshot_project, organization: organization, name: "Project 1", created_at: 2.days.ago)
      create(:screenshot_project, organization: organization, name: "Project 2", created_at: 1.day.ago)
      user.update!(plan_tier: :free)
      post switch_organization_path(organization)

      get settings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Usage exceeds plan limits")
      expect(response.body).to include("Screenshot projects")
      expect(response.body).to include("Project 2")
    end
  end

  describe "POST /billing/paddle/subscription_change" do
    let!(:billing_subscription) do
      BillingSubscription.create!(
        user: user,
        provider: "paddle",
        provider_subscription_id: "sub_change_123",
        provider_customer_id: "ctm_change_123",
        provider_plan_id: "pri_pro_monthly",
        status: "active",
        plan_tier: "pro",
        billing_interval: "monthly"
      )
    end

    before do
      sign_in user, scope: :user
    end

    it "applies an immediate pro to team upgrade" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_change_123").and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" }, "quantity" => 1 } ],
        "next_billed_at" => 30.days.from_now.iso8601
      )
      allow(client).to receive(:preview_subscription_update).and_return({ "update_summary" => [] })
      allow(client).to receive(:update_subscription).and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "customer_id" => "ctm_change_123",
        "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
        "custom_data" => { "user_id" => user.id },
        "current_billing_period" => {
          "starts_at" => "2026-03-25T10:00:00Z",
          "ends_at" => "2026-04-25T10:00:00Z"
        },
        "updated_at" => "2026-03-26T10:00:00Z"
      )

      post billing_paddle_subscription_change_path, params: {
        plan_tier: "team",
        billing_interval: "monthly"
      }

      expect(response).to redirect_to(pricing_path)
      follow_redirect!
      expect(response.body).to include("Team plan is active.")
      expect(user.reload.plan_tier).to eq("team")
    end

    it "schedules a team to pro downgrade and surfaces warnings about blocked organizations" do
      user.update!(plan_tier: :team)
      billing_subscription.update!(provider_plan_id: "pri_team_monthly", plan_tier: "team")
      5.times { |index| create(:organization, owner: user, name: "Org #{index + 1}") }

      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_change_123").and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_team_monthly" }, "quantity" => 1 } ],
        "next_billed_at" => 30.days.from_now.iso8601
      )
      allow(client).to receive(:preview_subscription_update).and_return({ "update_summary" => [] })
      allow(client).to receive(:update_subscription).and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "customer_id" => "ctm_change_123",
        "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
        "custom_data" => { "user_id" => user.id },
        "scheduled_change" => {
          "effective_at" => "2026-04-25T10:00:00Z",
          "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ]
        },
        "current_billing_period" => {
          "starts_at" => "2026-03-25T10:00:00Z",
          "ends_at" => "2026-04-25T10:00:00Z"
        },
        "updated_at" => "2026-03-26T10:00:00Z"
      )

      post billing_paddle_subscription_change_path, params: {
        plan_tier: "pro",
        billing_interval: "monthly"
      }

      expect(response).to redirect_to(pricing_path)
      follow_redirect!
      expect(response.body).to include("Pro Monthly is scheduled")
      expect(response.body).to include("Scheduled downgrade impact")
      expect(response.body).to include("2 organizations will be blocked")
      expect(response.body).to include("Org 5")
      get settings_path
      expect(response.body).to include("Scheduled downgrade impact")
      expect(response.body).to include("Org 5")
      expect(user.reload.plan_tier).to eq("team")
    end

    it "switches a pro subscription to yearly immediately without charging right away" do
      user.update!(plan_tier: :pro)

      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_change_123").and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" }, "quantity" => 1 } ],
        "next_billed_at" => 30.days.from_now.iso8601
      )
      allow(client).to receive(:preview_subscription_update).and_return({ "update_summary" => [] })
      allow(client).to receive(:update_subscription).and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "customer_id" => "ctm_change_123",
        "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
        "custom_data" => { "user_id" => user.id },
        "billing_cycle" => {
          "interval" => "year",
          "frequency" => 1
        },
        "current_billing_period" => {
          "starts_at" => "2026-03-26T10:00:00Z",
          "ends_at" => "2027-03-26T10:00:00Z"
        },
        "updated_at" => "2026-03-26T10:00:00Z"
      )

      post billing_paddle_subscription_change_path, params: {
        plan_tier: "pro",
        billing_interval: "yearly"
      }

      expect(response).to redirect_to(pricing_path)
      follow_redirect!
      expect(response.body).to include("Pro Yearly is active. No immediate charge was made.")
      expect(user.reload.plan_tier).to eq("pro")
      expect(billing_subscription.reload.plan_tier).to eq("pro")
      expect(billing_subscription.billing_interval).to eq("yearly")
      expect(response.body).not_to include("Switch to yearly")
      expect(response.body).to include("Current plan")
      expect(response.body).to include("Yearly")
    end

    it "removes a scheduled cancellation when a user switches from pro monthly to pro yearly" do
      user.update!(plan_tier: :pro)

      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_change_123").and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_pro_monthly" }, "quantity" => 1 } ],
        "next_billed_at" => 30.days.from_now.iso8601,
        "scheduled_change" => {
          "action" => "cancel",
          "effective_at" => "2026-04-25T10:00:00Z"
        }
      )
      allow(client).to receive(:preview_subscription_update).with(
        "sub_change_123",
        items: [ { price_id: "pri_pro_yearly", quantity: 1 } ],
        proration_billing_mode: "do_not_bill",
        on_payment_failure: "prevent_change",
        scheduled_change: nil
      ).and_return({ "update_summary" => [] })
      allow(client).to receive(:update_subscription).with(
        "sub_change_123",
        items: [ { price_id: "pri_pro_yearly", quantity: 1 } ],
        proration_billing_mode: "do_not_bill",
        on_payment_failure: "prevent_change",
        scheduled_change: nil
      ).and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "customer_id" => "ctm_change_123",
        "items" => [ { "price" => { "id" => "pri_pro_yearly" } } ],
        "custom_data" => { "user_id" => user.id },
        "current_billing_period" => {
          "starts_at" => "2026-03-26T10:00:00Z",
          "ends_at" => "2027-03-26T10:00:00Z"
        },
        "updated_at" => "2026-03-26T10:00:00Z"
      )

      post billing_paddle_subscription_change_path, params: {
        plan_tier: "pro",
        billing_interval: "yearly"
      }

      expect(response).to redirect_to(pricing_path)
      follow_redirect!
      expect(response.body).to include("Scheduled cancellation was removed.")
      expect(response.body).not_to include("Switch to yearly")
    end

    it "replaces a scheduled cancellation with a Team→Pro downgrade at renewal (atomic single-slot)" do
      user.update!(plan_tier: :team)
      billing_subscription.update!(provider_plan_id: "pri_team_monthly", plan_tier: "team")

      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_change_123").and_return(
        "id" => "sub_change_123",
        "status" => "active",
        "next_billed_at" => 30.days.from_now.iso8601,
        "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
        "scheduled_change" => { "action" => "cancel", "effective_at" => 30.days.from_now.iso8601 }
      )
      allow(client).to receive(:preview_subscription_update).and_return({})

      updated_payload = {
        "id" => "sub_change_123",
        "status" => "active",
        "items" => [ { "price" => { "id" => "pri_team_monthly" } } ],
        "scheduled_change" => {
          "action" => "update",
          "items" => [ { "price" => { "id" => "pri_pro_monthly" } } ],
          "effective_at" => 30.days.from_now.iso8601
        },
        "updated_at" => Time.current.iso8601,
        "current_billing_period" => { "ends_at" => 30.days.from_now.iso8601 }
      }
      expect(client).to receive(:update_subscription).and_return(updated_payload)

      post billing_paddle_subscription_change_path, params: {
        plan_tier: "pro",
        billing_interval: "monthly"
      }

      expect(response).to redirect_to(pricing_path)
      follow_redirect!
      expect(response.body).to include("scheduled")
      expect(response.body).not_to include("Remove the scheduled cancellation")
    end

    it "rejects unsupported interval jumps" do
      billing_subscription.update!(plan_tier: "team", billing_interval: "monthly", provider_plan_id: "pri_team_monthly")
      user.update!(plan_tier: :team)

      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)

      post billing_paddle_subscription_change_path, params: {
        plan_tier: "pro",
        billing_interval: "yearly"
      }

      expect(response).to redirect_to(pricing_path)
      follow_redirect!
      expect(response.body).to include("This subscription change is not supported yet.")
    end
  end

  describe "POST /billing/paddle/webhooks" do
    it "verifies and processes subscription webhooks idempotently" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)

      payload = {
        "event_id" => "evt_123",
        "event_type" => "subscription.updated",
        "occurred_at" => "2026-03-25T10:00:00Z",
        "data" => {
          "id" => "sub_999",
          "status" => "active",
          "customer_id" => "ctm_999",
          "items" => [ { "price" => { "id" => "pri_team_yearly" } } ],
          "custom_data" => { "user_id" => user.id },
          "current_billing_period" => {
            "starts_at" => "2026-03-25T10:00:00Z",
            "ends_at" => "2027-03-25T10:00:00Z"
          },
          "created_at" => "2026-03-25T10:00:00Z"
        }
      }

      signature = signed_paddle_signature(payload.to_json, ENV["PADDLE_WEBHOOK_SECRET"])

      expect {
        post billing_paddle_webhooks_path,
             params: payload.to_json,
             headers: {
               "CONTENT_TYPE" => "application/json",
               "Paddle-Signature" => signature
             }
      }.to have_enqueued_job(Billing::Paddle::ProcessWebhookEventJob)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true, "queued" => true)
      expect(BillingWebhookEvent.where(provider: "paddle", event_id: "evt_123").count).to eq(1)

      Billing::Paddle::ProcessWebhookEventJob.perform_now(BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_123").id)
      expect(user.reload.plan_tier).to eq("team")

      post billing_paddle_webhooks_path,
           params: payload.to_json,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "Paddle-Signature" => signature
           }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true, "duplicate" => true)
      expect(BillingWebhookEvent.where(provider: "paddle", event_id: "evt_123").count).to eq(1)
    end

    it "quarantines a webhook whose custom_data.user_id contradicts the existing subscription owner (no rebind, no trial reset)" do
      victim = create(:user, plan_tier: :free)
      attacker = create(:user, plan_tier: :free)

      victim_subscription = BillingSubscription.create!(
        user: victim,
        provider: "paddle",
        provider_subscription_id: "sub_idor_001",
        provider_customer_id: "ctm_idor_001",
        provider_plan_id: "pri_pro_monthly",
        status: "trialing",
        plan_tier: "pro",
        billing_interval: "monthly",
        provider_payload: {}
      )

      payload = {
        "event_id" => "evt_idor_001",
        "event_type" => "subscription.updated",
        "occurred_at" => "2026-03-25T10:00:00Z",
        "data" => {
          "id" => "sub_idor_001",
          "status" => "active",
          "customer_id" => "ctm_idor_001",
          "items" => [ { "price" => { "id" => "pri_team_yearly" } } ],
          "custom_data" => { "user_id" => attacker.id },
          "created_at" => "2026-03-25T10:00:00Z"
        }
      }

      signature = signed_paddle_signature(payload.to_json, ENV["PADDLE_WEBHOOK_SECRET"])

      post billing_paddle_webhooks_path,
           params: payload.to_json,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "Paddle-Signature" => signature
           }

      expect(response).to have_http_status(:ok)

      # The quarantined event is acknowledged as a no-op (logged + processed).
      expect {
        Billing::Paddle::ProcessWebhookEventJob.perform_now(
          BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_idor_001").id
        )
      }.not_to raise_error

      expect(BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_idor_001").processed_at).to be_present

      # Victim's subscription is completely untouched.
      victim_subscription.reload
      expect(victim_subscription.user_id).to eq(victim.id)
      expect(victim_subscription.plan_tier).to eq("pro")
      expect(victim_subscription.billing_interval).to eq("monthly")
      expect(victim_subscription.status).to eq("trialing")
      expect(BillingSubscription.where(user: attacker).count).to eq(0)
    end

    it "acknowledges simulated subscription events that do not map to a local user or price" do
      payload = {
        "event_id" => "evt_sim_subscription_123",
        "event_type" => "subscription.created",
        "occurred_at" => "2026-03-25T10:00:00Z",
        "data" => {
          "id" => "sub_sim_123",
          "status" => "active",
          "customer_id" => "ctm_sim_123",
          "items" => [ { "price" => { "id" => "pri_sim_unknown" } } ],
          "custom_data" => nil,
          "created_at" => "2026-03-25T10:00:00Z"
        }
      }

      signature = signed_paddle_signature(payload.to_json, ENV["PADDLE_WEBHOOK_SECRET"])

      expect {
        post billing_paddle_webhooks_path,
             params: payload.to_json,
             headers: {
               "CONTENT_TYPE" => "application/json",
               "Paddle-Signature" => signature
             }
      }.to have_enqueued_job(Billing::Paddle::ProcessWebhookEventJob)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true, "queued" => true)
      expect(BillingWebhookEvent.where(provider: "paddle", event_id: "evt_sim_subscription_123").count).to eq(1)

      Billing::Paddle::ProcessWebhookEventJob.perform_now(BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_sim_subscription_123").id)
      expect(BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_sim_subscription_123").processed_at).to be_present
      expect(BillingSubscription.find_by(provider_subscription_id: "sub_sim_123")).to be_nil
    end

    it "acknowledges simulated transaction events whose linked subscription is not one of our offerings" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_sim_456").and_return(
        "id" => "sub_sim_456",
        "status" => "active",
        "customer_id" => "ctm_sim_456",
        "items" => [ { "price" => { "id" => "pri_sim_unknown" } } ],
        "custom_data" => nil,
        "created_at" => "2026-03-25T10:00:00Z"
      )

      payload = {
        "event_id" => "evt_sim_transaction_456",
        "event_type" => "transaction.completed",
        "occurred_at" => "2026-03-25T10:05:00Z",
        "data" => {
          "id" => "txn_sim_456",
          "subscription_id" => "sub_sim_456"
        }
      }

      signature = signed_paddle_signature(payload.to_json, ENV["PADDLE_WEBHOOK_SECRET"])

      expect {
        post billing_paddle_webhooks_path,
             params: payload.to_json,
             headers: {
               "CONTENT_TYPE" => "application/json",
               "Paddle-Signature" => signature
             }
      }.to have_enqueued_job(Billing::Paddle::ProcessWebhookEventJob)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true, "queued" => true)
      expect(BillingWebhookEvent.where(provider: "paddle", event_id: "evt_sim_transaction_456").count).to eq(1)

      Billing::Paddle::ProcessWebhookEventJob.perform_now(BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_sim_transaction_456").id)
      expect(BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_sim_transaction_456").processed_at).to be_present
      expect(BillingSubscription.find_by(provider_subscription_id: "sub_sim_456")).to be_nil
    end

    it "acknowledges simulated transaction events when the linked subscription cannot be fetched" do
      client = instance_double(Billing::Paddle::Client)
      allow(Billing::Paddle::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_subscription).with("sub_sim_missing").and_raise(
        Billing::Paddle::Client::NotFoundError.new("Entity not found", status: 404)
      )

      payload = {
        "event_id" => "evt_sim_transaction_missing",
        "event_type" => "transaction.completed",
        "occurred_at" => "2026-03-25T10:06:00Z",
        "data" => {
          "id" => "txn_sim_missing",
          "subscription_id" => "sub_sim_missing"
        }
      }

      signature = signed_paddle_signature(payload.to_json, ENV["PADDLE_WEBHOOK_SECRET"])

      expect {
        post billing_paddle_webhooks_path,
             params: payload.to_json,
             headers: {
               "CONTENT_TYPE" => "application/json",
               "Paddle-Signature" => signature
             }
      }.to have_enqueued_job(Billing::Paddle::ProcessWebhookEventJob)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true, "queued" => true)
      expect(BillingWebhookEvent.where(provider: "paddle", event_id: "evt_sim_transaction_missing").count).to eq(1)

      Billing::Paddle::ProcessWebhookEventJob.perform_now(BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_sim_transaction_missing").id)
      expect(BillingWebhookEvent.find_by!(provider: "paddle", event_id: "evt_sim_transaction_missing").processed_at).to be_present
    end

    it "returns duplicate immediately for already processed webhook events" do
      payload = {
        "event_id" => "evt_already_processed",
        "event_type" => "subscription.updated",
        "occurred_at" => "2026-03-25T10:07:00Z",
        "data" => {
          "id" => "sub_already_processed"
        }
      }
      BillingWebhookEvent.create!(
        provider: "paddle",
        event_id: "evt_already_processed",
        event_type: "subscription.updated",
        verification_status: "verified",
        processed_at: Time.current,
        payload: payload
      )
      signature = signed_paddle_signature(payload.to_json, ENV["PADDLE_WEBHOOK_SECRET"])

      expect {
        post billing_paddle_webhooks_path,
             params: payload.to_json,
             headers: {
               "CONTENT_TYPE" => "application/json",
               "Paddle-Signature" => signature
             }
      }.not_to have_enqueued_job(Billing::Paddle::ProcessWebhookEventJob)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true, "duplicate" => true)
    end
  end

  def signed_paddle_signature(raw_body, secret)
    timestamp = Time.now.to_i
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}:#{raw_body}")
    "ts=#{timestamp};h1=#{digest}"
  end
end
