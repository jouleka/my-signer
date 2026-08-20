require "rails_helper"

RSpec.describe PaddleRedirectSafety, type: :controller do
  controller(ActionController::Base) do
    include Rails.application.routes.url_helpers
    include PaddleRedirectSafety

    def index
      render plain: safe_redirect_path(params[:candidate])
    end

    def sanitize
      render plain: sanitize_paddle_error(params[:msg], fallback: "fallback-text")
    end
  end

  before do
    routes.draw do
      get  "index"    => "anonymous#index"
      get  "sanitize" => "anonymous#sanitize"
    end
  end

  describe "#safe_redirect_path" do
    it "returns pricing_path when candidate and referer are both blank" do
      get :index
      expect(response.body).to eq("/pricing")
    end

    it "accepts a same-origin absolute URL" do
      request.env["HTTP_HOST"] = "mysigner.dev"
      get :index, params: { candidate: "http://mysigner.dev/billing" }
      expect(response.body).to eq("/billing")
    end

    it "rejects a cross-origin absolute URL" do
      request.env["HTTP_HOST"] = "mysigner.dev"
      get :index, params: { candidate: "https://attacker.example/evil" }
      expect(response.body).to eq("/pricing")
    end

    it "accepts a path-only candidate that starts with /" do
      get :index, params: { candidate: "/billing/portal" }
      expect(response.body).to eq("/billing/portal")
    end

    it "rejects a protocol-relative URL (//evil.com)" do
      get :index, params: { candidate: "//attacker.example/evil" }
      expect(response.body).to eq("/pricing")
    end

    it "rejects a malformed URL" do
      get :index, params: { candidate: "http://[not-a-uri" }
      expect(response.body).to eq("/pricing")
    end

    it "falls back to same-origin referer when candidate is blank" do
      request.env["HTTP_HOST"]    = "mysigner.dev"
      request.env["HTTP_REFERER"] = "http://mysigner.dev/dashboard"
      get :index
      expect(response.body).to eq("/dashboard")
    end

    it "rejects a cross-origin referer when candidate is blank" do
      request.env["HTTP_HOST"]    = "mysigner.dev"
      request.env["HTTP_REFERER"] = "https://attacker.example/dashboard"
      get :index
      expect(response.body).to eq("/pricing")
    end
  end

  describe "#sanitize_paddle_error" do
    it "returns the fallback when the message is blank" do
      get :sanitize, params: { msg: "" }
      expect(response.body).to eq("fallback-text")
    end

    it "redacts Paddle resource IDs" do
      get :sanitize, params: { msg: "Subscription sub_01abc cannot be modified in txn_XYZ." }
      expect(response.body).to include("[redacted]")
      expect(response.body).not_to include("sub_01abc")
      expect(response.body).not_to include("txn_XYZ")
    end

    it "reduces a message that is only a Paddle ID to the redaction token" do
      get :sanitize, params: { msg: "sub_abc" }
      expect(response.body).to eq("[redacted]")
    end
  end
end
