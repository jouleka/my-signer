require "rails_helper"

RSpec.describe "AppleAdsCredentials", type: :request do
  let(:user) { create(:user, :team_plan) }
  let(:org) { create(:organization, owner: user) }
  let(:pem) { SpecCredentialFixtures.ec_private_key }
  let(:valid_params) do
    { apple_ads_credential: {
      client_id: "SEARCHADS.00000000-0000-0000-0000-000000000000",
      team_id: "1234567890",
      key_id: "ABCDEF1234",
      private_key_pem: pem
    } }
  end

  before do
    sign_in user
    # Stub the actual Apple OAuth roundtrip — controller should call Client#access_token.
    # Keeping this at the outer `before` ensures update + destroy specs that also
    # reach verify_connection! have the network mocked.
    @mock_client = instance_double(Aso::AppleAds::Client)
    allow(Aso::AppleAds::Client).to receive(:new).and_return(@mock_client)
    allow(@mock_client).to receive(:access_token).and_return("test-token")
  end

  describe "GET new" do
    it "renders when no credential exists" do
      get new_organization_apple_ads_credential_path(org)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST create" do
    it "creates the credential + marks success" do
      expect {
        post organization_apple_ads_credential_path(org), params: valid_params
      }.to change { AppleAdsCredential.count }.by(1)
      cred = AppleAdsCredential.last
      expect(cred.last_successful_at).to be_present
    end

    it "redirects to keywords page on success" do
      post organization_apple_ads_credential_path(org), params: valid_params
      expect(response).to redirect_to(organization_keywords_path(org))
    end

    it "logs an apple_ads_credential_added audit event" do
      expect(Audit::Logger).to receive(:log).with(
        hash_including(action: :apple_ads_credential_added, organization: org, actor: user)
      )
      post organization_apple_ads_credential_path(org), params: valid_params
    end

    it "renders :new with status 422 on invalid params (bad PEM)" do
      bad_params = valid_params.deep_dup
      bad_params[:apple_ads_credential][:private_key_pem] = "not a pem"
      post organization_apple_ads_credential_path(org), params: bad_params
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "saves with last_error when OAuth fails" do
      allow(@mock_client).to receive(:access_token).and_raise(Aso::AppleAds::CredentialsInvalid, "401")
      post organization_apple_ads_credential_path(org), params: valid_params
      cred = AppleAdsCredential.last
      expect(cred).to be_present
      expect(cred.last_error).to include("401")
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "DENIES developer members (admin_or_owner? gate)" do
      dev = create(:user)
      org.memberships.create!(user: dev, role: :developer)
      sign_in dev
      post organization_apple_ads_credential_path(org), params: valid_params
      # Pundit::NotAuthorizedError is rescued in ApplicationController and
      # redirects with an alert; confirm no credential was created.
      expect(AppleAdsCredential.where(organization: org).count).to eq(0)
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_present
    end

    it "DENIES outsiders" do
      outsider = create(:user, :pro_plan)
      sign_in outsider
      post organization_apple_ads_credential_path(org), params: valid_params
      expect(AppleAdsCredential.where(organization: org).count).to eq(0)
      # set_organization now scopes the org lookup to current_user.organizations,
      # so an outsider sees 404 — same response as a non-existent org id, which
      # closes the enumeration oracle (302 = exists but not mine; 404 = doesn't
      # exist). See OrganizationsController#set_organization.
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH update" do
    let!(:cred) { create(:apple_ads_credential, organization: org, last_successful_at: 1.day.ago) }

    it "updates fields + re-verifies connection" do
      patch organization_apple_ads_credential_path(org),
            params: { apple_ads_credential: {
              client_id: "SEARCHADS.11111111-1111-1111-1111-111111111111",
              team_id: cred.team_id,
              key_id: cred.key_id,
              private_key_pem: cred.private_key_pem
            } }
      expect(cred.reload.client_id).to eq("SEARCHADS.11111111-1111-1111-1111-111111111111")
    end
  end

  describe "DELETE destroy" do
    let!(:cred) { create(:apple_ads_credential, organization: org) }

    it "destroys the credential" do
      expect {
        delete organization_apple_ads_credential_path(org)
      }.to change { AppleAdsCredential.count }.by(-1)
    end

    it "logs an apple_ads_credential_removed audit event" do
      expect(Audit::Logger).to receive(:log).with(
        hash_including(action: :apple_ads_credential_removed, organization: org, actor: user)
      )
      delete organization_apple_ads_credential_path(org)
    end
  end

  describe "new/create when credential already exists" do
    it "redirects new to edit when credential already exists" do
      create(:apple_ads_credential, organization: org)
      get new_organization_apple_ads_credential_path(org)
      expect(response).to redirect_to(edit_organization_apple_ads_credential_path(org))
    end

    it "redirects create to edit when credential already exists" do
      create(:apple_ads_credential, organization: org)
      post organization_apple_ads_credential_path(org), params: valid_params
      expect(response).to redirect_to(edit_organization_apple_ads_credential_path(org))
      expect(flash[:alert]).to include("already connected")
    end
  end

  describe "private_key_pem handling" do
    it "does NOT echo private_key_pem back in the response body on validation failure" do
      bad_params = valid_params.deep_dup
      bad_params[:apple_ads_credential][:client_id] = ""  # trigger validation failure
      post organization_apple_ads_credential_path(org), params: bad_params
      expect(response.body).not_to include("BEGIN EC PRIVATE KEY")
      expect(response.body).not_to include(pem)
    end

    it "preserves existing private_key_pem on update when field is blank" do
      cred = create(:apple_ads_credential, organization: org)
      original_key = cred.private_key_pem
      patch organization_apple_ads_credential_path(org),
            params: { apple_ads_credential: { client_id: "SEARCHADS.NEW", team_id: cred.team_id, key_id: cred.key_id, private_key_pem: "" } }
      expect(cred.reload.private_key_pem).to eq(original_key)
      expect(cred.client_id).to eq("SEARCHADS.NEW")
    end
  end
end
