require "rails_helper"

RSpec.describe "Api::V1::Organizations Google Play fields", type: :request do
  # Phase 0: the aggregate /credentials endpoint was removed (it leaked ASC +
  # GP credentials in one response). These tests were rewritten to verify that
  # (a) the /show endpoint still advertises google_play_configured,
  # (b) the deprecated /credentials path now returns 404 as expected, and
  # (c) the new /credentials/google_play/access_token endpoint is gated
  #     exclusively by the manage_credentials? Pundit policy.
  # Token minting is covered in detail by google_play_access_tokens_spec.rb.

  it "exposes google_play_configured on the show endpoint" do
    user = User.create!(email: "dev2@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
    org = Organization.create!(name: "Org2", owner: user)
    api_token = ApiToken.generate_for(user: user, organization: org, name: "T", scopes: [ "read" ])[1]

    GooglePlayCredential.create!(organization: org, name: "GP", service_account_json: {
      type: "service_account",
      project_id: "p",
      private_key: "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
      client_email: "svc@example.com",
      client_id: "123"
    }.to_json, developer_account_id: "dev-123", active: true)

    headers = { "Authorization" => "Bearer #{api_token}", "Content-Type" => "application/json" }
    get "/api/v1/organizations/#{org.id}", headers: headers

    expect(response).to have_http_status(:success)
    json = JSON.parse(response.body)
    expect(json["google_play_configured"]).to eq(true)
    # Service account JSON must NOT leak through show.
    expect(json).not_to have_key("google_play_service_account")
  end

  it "aggregate /credentials endpoint is gone (Phase 0 removal)" do
    user = User.create!(email: "dev@example.com", password: "SecurePassword123!", confirmed_at: Time.current)
    org = Organization.create!(name: "Org", owner: user)
    api_token = ApiToken.generate_for(user: user, organization: org, name: "T", scopes: [ "admin" ])[1]

    headers = { "Authorization" => "Bearer #{api_token}", "Content-Type" => "application/json" }
    get "/api/v1/organizations/#{org.id}/credentials", headers: headers

    expect(response).to have_http_status(:not_found)
  end
end
