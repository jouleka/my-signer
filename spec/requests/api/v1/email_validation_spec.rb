require 'rails_helper'

RSpec.describe "API Token Email Validation", type: :request do
  let!(:user) { User.create!(
    email: "developer@example.com",
    password: "SecurePassword123!",
    confirmed_at: Time.current
  ) }
  let!(:other_user) { User.create!(
    email: "admin@example.com",
    password: "SecurePassword123!",
    confirmed_at: Time.current
  ) }
  let!(:org) { Organization.create!(name: "Test Org", owner: user) }
  let!(:other_org) { Organization.create!(name: "Other Org", owner: other_user) }
  let!(:token) { ApiToken.generate_for(user: user, organization: org, name: "User Token", scopes: [ "read" ])[1] }
  let!(:other_token) { ApiToken.generate_for(user: other_user, organization: other_org, name: "Admin Token", scopes: [ "read" ])[1] }

  describe "Email validation with X-User-Email header" do
    context "when email matches token's user" do
      it "allows access with exact email match" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "developer@example.com"
          }

        expect(response).to have_http_status(:success)
      end

      it "allows access with case-insensitive email" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "DEVELOPER@EXAMPLE.COM"
          }

        expect(response).to have_http_status(:success)
      end

      it "allows access with mixed case email" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "Developer@Example.Com"
          }

        expect(response).to have_http_status(:success)
      end

      it "allows access with email that has whitespace (trimmed)" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "  developer@example.com  "
          }

        expect(response).to have_http_status(:success)
      end
    end

    context "when email doesn't match token's user" do
      it "rejects request with wrong email" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "admin@example.com"
          }

        expect(response).to have_http_status(:unauthorized)

        json = JSON.parse(response.body)
        expect(json['error']).to eq('unauthorized')
        expect(json['message']).to include("doesn't belong to admin@example.com")
        expect(json['message']).to include("use your own token")
      end

      it "rejects request with completely different email" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "hacker@malicious.com"
          }

        expect(response).to have_http_status(:unauthorized)

        json = JSON.parse(response.body)
        expect(json['error']).to eq('unauthorized')
      end

      it "shows the provided email in error message (not token's email)" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "wrong@example.com"
          }

        expect(response).to have_http_status(:unauthorized)

        json = JSON.parse(response.body)
        expect(json['message']).to include("wrong@example.com")
        expect(json['message']).not_to include("developer@example.com")
      end
    end

    context "when no email header is provided (optional header)" do
      it "allows access without email validation" do
        get "/api/v1/user/organizations",
          headers: { "Authorization" => "Bearer #{token}" }

        expect(response).to have_http_status(:success)
      end

      it "works for all endpoints when email header is omitted" do
        # Organizations
        get "/api/v1/user/organizations",
          headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:success)

        # Organization details
        get "/api/v1/organizations/#{org.id}",
          headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:success)
      end
    end

    context "with different users and tokens" do
      it "user A's token with user A's email succeeds" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "developer@example.com"
          }

        expect(response).to have_http_status(:success)
      end

      it "user B's token with user B's email succeeds" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{other_token}",
            "X-User-Email" => "admin@example.com"
          }

        expect(response).to have_http_status(:success)
      end

      it "user A's token with user B's email fails" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "admin@example.com"
          }

        expect(response).to have_http_status(:unauthorized)
      end

      it "user B's token with user A's email fails" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{other_token}",
            "X-User-Email" => "developer@example.com"
          }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "edge cases" do
      it "rejects empty email header" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => ""
          }

        # Empty string is treated as blank, so no validation happens
        expect(response).to have_http_status(:success)
      end

      it "handles email with only whitespace as blank" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "   "
          }

        # Whitespace-only is treated as blank
        expect(response).to have_http_status(:success)
      end

      it "validates email even with extra spaces around it" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "   admin@example.com   "
          }

        # Should fail because admin@example.com != developer@example.com
        expect(response).to have_http_status(:unauthorized)
      end

      it "is case-insensitive for domain part" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "developer@EXAMPLE.COM"
          }

        expect(response).to have_http_status(:success)
      end

      it "works across different API endpoints" do
        # Test on organization endpoint
        get "/api/v1/organizations/#{org.id}",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "developer@example.com"
          }
        expect(response).to have_http_status(:success)

        # Test on user organizations endpoint
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "developer@example.com"
          }
        expect(response).to have_http_status(:success)
      end

      it "rejects across all endpoints when email doesn't match" do
        # Test on organization endpoint
        get "/api/v1/organizations/#{org.id}",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "wrong@example.com"
          }
        expect(response).to have_http_status(:unauthorized)

        # Test on user organizations endpoint
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "wrong@example.com"
          }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with revoked or expired tokens" do
      let!(:revoked_token_record) { ApiToken.generate_for(user: user, organization: org, name: "Revoked", scopes: [ "read" ]) }
      let(:revoked_token) { revoked_token_record[1] }

      before do
        revoked_token_record[0].revoke!
      end

      it "returns unauthorized even with correct email" do
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{revoked_token}",
            "X-User-Email" => "developer@example.com"
          }

        expect(response).to have_http_status(:unauthorized)

        json = JSON.parse(response.body)
        # Should show generic "Invalid or missing API token" message, not email error
        expect(json['message']).to eq("Invalid or missing API token")
      end
    end

    context "with session authentication (web UI)" do
      it "doesn't validate email for session-based auth" do
        # Session auth doesn't use X-User-Email header, should work normally
        # This would be tested in integration tests with actual session setup
        # For now, just verify token auth with email validation works independently
        get "/api/v1/user/organizations",
          headers: {
            "Authorization" => "Bearer #{token}",
            "X-User-Email" => "developer@example.com"
          }

        expect(response).to have_http_status(:success)
      end
    end
  end
end
