require "rails_helper"

RSpec.describe Billing::Paddle::Client do
  around do |example|
    original_provider = ENV["BILLING_PROVIDER"]
    original_env = ENV["PADDLE_ENV"]
    original_api_key = ENV["PADDLE_API_KEY"]

    ENV["BILLING_PROVIDER"] = "paddle"
    ENV["PADDLE_ENV"] = "sandbox"
    ENV["PADDLE_API_KEY"] = "pdl_sdbx_apikey_test"
    example.run
  ensure
    ENV["BILLING_PROVIDER"] = original_provider
    ENV["PADDLE_ENV"] = original_env
    ENV["PADDLE_API_KEY"] = original_api_key
  end

  describe "initialization" do
    it "uses the sandbox API base for sandbox credentials" do
      fake_conn = instance_double(Faraday::Connection)
      allow(Faraday).to receive(:new).and_return(fake_conn)

      described_class.new

      expect(Faraday).to have_received(:new).with(hash_including(url: "https://sandbox-api.paddle.com"))
    end
  end

  describe "#clear_scheduled_change" do
    it "sends PATCH /subscriptions/{id} with only scheduled_change: null in the body" do
      fake_conn = instance_double(Faraday::Connection)
      response = instance_double(
        Faraday::Response,
        status: 200,
        body: { data: { "id" => "sub_abc", "scheduled_change" => nil } }.to_json
      )

      req = Object.new
      captured_body = nil
      captured_path = nil
      req.define_singleton_method(:url) { |p| captured_path = p }
      req.define_singleton_method(:headers) { @h ||= {} }
      req.define_singleton_method(:params) { @p ||= {} }
      req.define_singleton_method(:body=) { |b| captured_body = b }

      allow(Faraday).to receive(:new).and_return(fake_conn)
      allow(fake_conn).to receive(:patch).and_yield(req).and_return(response)

      described_class.new.clear_scheduled_change("sub_abc")

      expect(captured_path).to eq("subscriptions/sub_abc")
      expect(JSON.parse(captured_body)).to eq({ "scheduled_change" => nil })
    end
  end

  describe "#parse!" do
    let(:client) { described_class.new }

    it "returns the data payload for successful responses" do
      response = instance_double(Faraday::Response, status: 200, body: { data: { id: "txn_123" } }.to_json)

      expect(client.send(:parse!, response)).to eq({ "id" => "txn_123" })
    end

    it "raises a readable message for Paddle hash-shaped errors" do
      response = instance_double(
        Faraday::Response,
        status: 403,
        body: { error: { detail: "You aren't permitted to perform this request." } }.to_json
      )

      expect { client.send(:parse!, response) }.to raise_error(StandardError, "You aren't permitted to perform this request.")
    end

    it "raises AlreadyCancelledError for the HTTP 400 'cancel a cancelled sub' response" do
      response = instance_double(
        Faraday::Response,
        status: 400,
        body: {
          error: {
            type: "request_error",
            code: "subscription_is_canceled_action_invalid",
            detail: "Cannot perform this action on a canceled subscription"
          }
        }.to_json
      )

      expect { client.send(:parse!, response) }
        .to raise_error(Billing::Paddle::Client::AlreadyCancelledError) { |e|
          expect(e.status).to eq(400)
          expect(e.code).to eq("subscription_is_canceled_action_invalid")
        }
    end

    it "raises AlreadyCancelledError for the HTTP 400 'update a cancelled sub' response" do
      response = instance_double(
        Faraday::Response,
        status: 400,
        body: { error: { code: "subscription_update_when_canceled", detail: "Cannot update" } }.to_json
      )

      expect { client.send(:parse!, response) }
        .to raise_error(Billing::Paddle::Client::AlreadyCancelledError)
    end

    it "raises NotFoundError for HTTP 404 (subscription deleted on Paddle's side)" do
      response = instance_double(
        Faraday::Response,
        status: 404,
        body: { error: { code: "entity_not_found", detail: "Not found" } }.to_json
      )

      expect { client.send(:parse!, response) }
        .to raise_error(Billing::Paddle::Client::NotFoundError)
    end

    it "raises a generic Error (not AlreadyCancelledError) for unrelated 400s" do
      response = instance_double(
        Faraday::Response,
        status: 400,
        body: { error: { code: "validation_error", detail: "items is required" } }.to_json
      )

      expect { client.send(:parse!, response) }
        .to raise_error(Billing::Paddle::Client::Error) { |e|
          expect(e).not_to be_a(Billing::Paddle::Client::AlreadyCancelledError)
          expect(e.code).to eq("validation_error")
        }
    end
  end
end
