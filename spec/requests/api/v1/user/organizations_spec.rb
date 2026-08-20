require 'rails_helper'

RSpec.describe "Api::V1::User::Organizations", type: :request do
  let!(:user) { User.create!(email: "test@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro) }
  let!(:org1) { Organization.create!(name: "Org 1", owner: user) }
  let!(:org2) { Organization.create!(name: "Org 2", owner: user) }
  let!(:other_user) { User.create!(email: "other@example.com", password: "SecurePassword123!", confirmed_at: Time.current) }
  let!(:org3) { Organization.create!(name: "Org 3", owner: other_user) }

  describe "GET /api/v1/user/organizations" do
    context "with org-specific token for org1" do
      let!(:token1) { ApiToken.generate_for(user: user, organization: org1, name: "Token 1", scopes: [ "read" ])[1] }

      it "returns ALL organizations the user is a member of, not just token's org" do
        # User is owner of org1 and org2
        get "/api/v1/user/organizations", headers: { "Authorization" => "Bearer #{token1}" }

        expect(response).to have_http_status(:success)

        json = JSON.parse(response.body)
        org_ids = json['organizations'].map { |o| o['id'] }

        expect(org_ids).to include(org1.id, org2.id)
        expect(org_ids).not_to include(org3.id)
        expect(json['total']).to eq(2)
      end

      it "includes org details and roles" do
        get "/api/v1/user/organizations", headers: { "Authorization" => "Bearer #{token1}" }

        expect(response).to have_http_status(:success)

        json = JSON.parse(response.body)
        org1_data = json['organizations'].find { |o| o['id'] == org1.id }

        expect(org1_data['name']).to eq("Org 1")
        expect(org1_data['role']).to eq("owner")
        expect(org1_data['plan']['tier']).to eq("pro")
        expect(org1_data["plan"]).to have_key("entitlements")
        expect(org1_data["plan"]).to have_key("usage")
        expect(org1_data).not_to have_key("member_count")
      end
    end

    context "when user is member of multiple orgs with different roles" do
      let!(:org4_owner) { User.create!(email: "owner@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :team) }
      let!(:org4) { Organization.create!(name: "Org 4", owner: org4_owner) }
      let!(:membership) { org4.memberships.create!(user: user, role: :developer) }
      let!(:token1) { ApiToken.generate_for(user: user, organization: org1, name: "Token 1", scopes: [ "read" ])[1] }

      it "returns all orgs with correct roles" do
        get "/api/v1/user/organizations", headers: { "Authorization" => "Bearer #{token1}" }

        expect(response).to have_http_status(:success)

        json = JSON.parse(response.body)

        org1_data = json['organizations'].find { |o| o['id'] == org1.id }
        org4_data = json['organizations'].find { |o| o['id'] == org4.id }

        expect(org1_data['role']).to eq("owner")
        expect(org4_data['role']).to eq("developer")
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        get "/api/v1/user/organizations"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with read scope" do
      let!(:token) { ApiToken.generate_for(user: user, organization: org1, name: "Read Token", scopes: [ "read" ])[1] }

      it "allows access" do
        get "/api/v1/user/organizations", headers: { "Authorization" => "Bearer #{token}" }
        expect(response).to have_http_status(:success)
      end
    end

    context "with session authentication" do
      before do
        sign_in user, scope: :user
      end

      it "includes the full plan snapshot for first-party web requests" do
        get "/api/v1/user/organizations"

        expect(response).to have_http_status(:success)

        json = JSON.parse(response.body)
        org1_data = json["organizations"].find { |o| o["id"] == org1.id }

        expect(org1_data["member_count"]).to be >= 1
        expect(org1_data["plan"]["tier"]).to eq("pro")
        expect(org1_data["plan"]).to have_key("entitlements")
        expect(org1_data["plan"]).to have_key("usage")
      end
    end
  end
end
