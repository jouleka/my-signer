require "rails_helper"

RSpec.describe "Billing Paddle ScheduledChanges", type: :request do
  let(:user) { create(:user, :team_plan) }
  let!(:organization) { create(:organization, owner: user) }

  around do |example|
    original = ENV.to_hash.slice(
      "BILLING_PROVIDER",
      "PADDLE_ENV",
      "PADDLE_API_KEY",
      "PADDLE_PRO_YEARLY_PRICE_ID",
      "PADDLE_TEAM_YEARLY_PRICE_ID"
    )

    ENV["BILLING_PROVIDER"] = "paddle"
    ENV["PADDLE_ENV"] = "sandbox"
    ENV["PADDLE_API_KEY"] = "pdl_sdbx_apikey_test"
    ENV["PADDLE_PRO_YEARLY_PRICE_ID"] = "pri_pro_yearly"
    ENV["PADDLE_TEAM_YEARLY_PRICE_ID"] = "pri_team_yearly"

    example.run
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  before { sign_in user, scope: :user }

  describe "DELETE /billing/paddle/scheduled_change" do
    context "when a plan-downgrade is scheduled" do
      let!(:subscription) do
        create(:billing_subscription, :with_scheduled_pro_downgrade, user: user)
      end

      it "calls Paddle's clear_scheduled_change and redirects with success flash" do
        cleared_payload = subscription.provider_payload.merge(
          "scheduled_change" => nil,
          "updated_at" => Time.current.iso8601
        )

        client = instance_double(Billing::Paddle::Client)
        allow(Billing::Paddle::Client).to receive(:new).and_return(client)
        expect(client).to receive(:clear_scheduled_change).with(subscription.provider_subscription_id).and_return(cleared_payload)

        synchronizer = instance_double(Billing::Paddle::Synchronizer)
        allow(Billing::Paddle::Synchronizer).to receive(:new).and_return(synchronizer)
        expect(synchronizer).to receive(:synchronize_subscription_payload!).and_return(subscription)

        delete billing_paddle_scheduled_change_path, headers: { "HTTP_REFERER" => pricing_url }

        expect(flash[:notice]).to match(/will continue/i)
        expect(response).to redirect_to(pricing_path)
      end

      it "records a schedule_cleared AuditEvent with :downgrade schedule_kind" do
        cleared_payload = subscription.provider_payload.merge("scheduled_change" => nil)
        client = instance_double(Billing::Paddle::Client)
        allow(Billing::Paddle::Client).to receive(:new).and_return(client)
        allow(client).to receive(:clear_scheduled_change).and_return(cleared_payload)
        synchronizer = instance_double(Billing::Paddle::Synchronizer)
        allow(Billing::Paddle::Synchronizer).to receive(:new).and_return(synchronizer)
        allow(synchronizer).to receive(:synchronize_subscription_payload!).and_return(subscription)

        allow(Billing::Configuration).to receive(:paddle_price_id_for) do |tier:, interval:|
          "pri_#{tier}_#{interval}"
        end

        expect {
          delete billing_paddle_scheduled_change_path, headers: { "HTTP_REFERER" => pricing_url }
        }.to change { AuditEvent.where(action: "schedule_cleared").count }.by_at_least(1)

        event = AuditEvent.where(action: "schedule_cleared").last
        expect(event.metadata["schedule_kind"]).to eq("downgrade")
      end
    end

    context "when no schedule is pending (idempotent)" do
      let!(:subscription) do
        create(:billing_subscription, :team_yearly, user: user)
      end

      it "does not call Paddle and flashes 'already cleared'" do
        expect_any_instance_of(Billing::Paddle::Client).not_to receive(:clear_scheduled_change)

        delete billing_paddle_scheduled_change_path, headers: { "HTTP_REFERER" => pricing_url }

        expect(flash[:notice]).to match(/no scheduled change/i)
        expect(response).to redirect_to(pricing_path)
      end
    end

    context "when Paddle rejects the update (renewal-window lock)" do
      let!(:subscription) do
        create(:billing_subscription, :team_yearly, :with_scheduled_cancel, user: user)
      end

      it "surfaces a sanitized Paddle error message in the flash" do
        client = instance_double(Billing::Paddle::Client)
        allow(Billing::Paddle::Client).to receive(:new).and_return(client)
        allow(client).to receive(:clear_scheduled_change).and_raise(
          Billing::Paddle::Client::Error.new("Cannot modify subscription sub_abc within 30 minutes of renewal.")
        )

        delete billing_paddle_scheduled_change_path, headers: { "HTTP_REFERER" => pricing_url }

        expect(flash[:alert]).to match(/30 minutes/i)
        expect(flash[:alert]).not_to include("sub_abc")
        expect(flash[:alert]).to include("[redacted]")
      end
    end

    context "when referer is a different origin (open-redirect defense)" do
      let!(:subscription) do
        create(:billing_subscription, :team_yearly, user: user)
      end

      it "redirects to pricing_path instead of the untrusted referer" do
        delete billing_paddle_scheduled_change_path, headers: { "HTTP_REFERER" => "https://attacker.example/evil" }

        expect(response).to redirect_to(pricing_path)
      end
    end

    context "when user has no subscription at all" do
      it "returns idempotent success without touching Paddle" do
        expect_any_instance_of(Billing::Paddle::Client).not_to receive(:clear_scheduled_change)

        delete billing_paddle_scheduled_change_path, headers: { "HTTP_REFERER" => pricing_url }

        expect(flash[:notice]).to match(/no scheduled change/i)
      end
    end
  end
end
