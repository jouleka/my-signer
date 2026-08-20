require "rails_helper"

RSpec.describe "Legal pages", type: :request do
  it "allows guests to view terms of service" do
    get terms_of_service_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Terms of Service")
    expect(response.body).to include("MySigner")
    expect(response.body).to include("Merchant of Record")
    expect(response.body).to include("handles returns")
  end

  it "allows guests to view the privacy policy" do
    get privacy_policy_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Privacy Policy")
    expect(response.body).to include("support@mysigner.dev")
  end

  it "allows guests to view the refund policy" do
    get refund_policy_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Refund Policy")
    expect(response.body).to include("legal/buyer-terms")
    expect(response.body).to include("current billing period")
  end

  it "links legal pages and pricing from the public footer" do
    get unauthenticated_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(pricing_path)
    expect(response.body).to include(terms_of_service_path)
    expect(response.body).to include(privacy_policy_path)
    expect(response.body).to include(refund_policy_path)
  end

  it "includes refund alongside the other public links in guest navigation" do
    get pricing_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(terms_of_service_path)
    expect(response.body).to include(privacy_policy_path)
    expect(response.body).to include(refund_policy_path)
  end
end
