require 'rails_helper'

RSpec.describe ApiToken, type: :model do
  let(:user) { User.create!(email: "test@example.com", password: "SecurePassword123!", confirmed_at: Time.current, plan_tier: :pro) }
  let(:organization) { Organization.create!(name: "Test Org", owner: user) }
  let(:other_org) { Organization.create!(name: "Other Org", owner: user) }

  describe "associations" do
    it "belongs to organization" do
      token = ApiToken.new
      expect(token).to respond_to(:organization)
    end

    it "belongs to user" do
      token = ApiToken.new
      expect(token).to respond_to(:user)
    end
  end

  describe "validations" do
    it "validates presence of name" do
      token = ApiToken.new(user: user, organization: organization, token_digest: "abc")
      expect(token).not_to be_valid
      expect(token.errors[:name]).to include("can't be blank")
    end

    it "validates length of name" do
      token = ApiToken.new(name: "a" * 101, user: user, organization: organization, token_digest: "abc")
      expect(token).not_to be_valid
      expect(token.errors[:name]).to include("is too long (maximum is 100 characters)")
    end

    it "validates presence of token_digest" do
      token = ApiToken.new(name: "Test", user: user, organization: organization)
      expect(token).not_to be_valid
      expect(token.errors[:token_digest]).to include("can't be blank")
    end

    it "validates uniqueness of token_digest" do
      ApiToken.create!(name: "Test1", user: user, organization: organization, token_digest: "abc123")
      token = ApiToken.new(name: "Test2", user: user, organization: organization, token_digest: "abc123")
      expect(token).not_to be_valid
      expect(token.errors[:token_digest]).to include("has already been taken")
    end

    it "validates presence of organization" do
      token = ApiToken.new(name: "Test", user: user, token_digest: "abc")
      expect(token).not_to be_valid
      expect(token.errors[:organization]).to include("must exist")
    end

    it "validates presence of user" do
      token = ApiToken.new(name: "Test", organization: organization, token_digest: "abc")
      expect(token).not_to be_valid
      expect(token.errors[:user]).to include("must exist")
    end

    context "scopes validation" do
      it "accepts valid scopes" do
        token = ApiToken.new(name: "Test", user: user, organization: organization, token_digest: "abc", scopes: "read,write")
        expect(token).to be_valid
      end

      it "accepts admin scope" do
        token = ApiToken.new(name: "Test", user: user, organization: organization, token_digest: "abc", scopes: "admin")
        expect(token).to be_valid
      end

      it "rejects invalid scopes" do
        token = ApiToken.new(name: "Test", user: user, organization: organization, token_digest: "abc", scopes: "read,invalid")
        expect(token).not_to be_valid
        expect(token.errors[:scopes]).to include("contains invalid scopes: invalid")
      end
    end
  end

  describe "organization requirement" do
    it "cannot create token without organization" do
      token = ApiToken.new(name: "Test", user: user, token_digest: "abc123")
      expect(token).not_to be_valid
      expect(token.errors[:organization]).to include("must exist")
    end

    it "cannot create token with nil organization" do
      expect {
        ApiToken.create!(name: "Test", user: user, organization: nil, token_digest: "abc123")
      }.to raise_error(ActiveRecord::RecordInvalid, /Organization must exist/)
    end

    it "cannot save token without organization via database constraint" do
      # Bypass validations to test DB constraint
      token = ApiToken.new(name: "Test", user: user, token_digest: "abc123")

      expect {
        token.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "cannot update token to remove organization" do
      token, _ = ApiToken.generate_for(user: user, organization: organization, name: "Test")

      expect {
        token.update!(organization_id: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "cannot update token to nil organization via update_columns" do
      token, _ = ApiToken.generate_for(user: user, organization: organization, name: "Test")

      expect {
        token.update_columns(organization_id: nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "rejects invalid organization_id (validation first, then FK)" do
      # Validation catches this before FK constraint
      expect {
        ApiToken.create!(name: "Test", user: user, organization_id: 999999, token_digest: "abc123")
      }.to raise_error(ActiveRecord::RecordInvalid, /Organization must exist/)
    end
  end

  describe ".generate_for" do
    it "requires organization parameter" do
      expect {
        ApiToken.generate_for(user: user, name: "Test")
      }.to raise_error(ArgumentError)
    end

    it "creates token with organization" do
      token, plain = ApiToken.generate_for(user: user, organization: organization, name: "Test")

      expect(token.organization_id).to eq(organization.id)
      expect(token.organization).to eq(organization)
    end

    it "creates token with correct attributes" do
      token, plain = ApiToken.generate_for(
        user: user,
        organization: organization,
        name: "Test Token",
        scopes: [ "read", "write" ]
      )

      expect(token).to be_persisted
      expect(token.name).to eq("Test Token")
      expect(token.user).to eq(user)
      expect(token.organization).to eq(organization)
      expect(token.scopes).to eq("read,write")
      expect(token.revoked).to be false
      expect(plain).to be_present
    end

    it "creates token with default scopes" do
      token, _ = ApiToken.generate_for(user: user, organization: organization, name: "Test")
      expect(token.scopes).to eq("read")
    end

    it "creates token with expiration" do
      token, _ = ApiToken.generate_for(
        user: user,
        organization: organization,
        name: "Test",
        expires_in: 30.days
      )

      expect(token.expires_at).to be_present
      expect(token.expires_at).to be_within(1.minute).of(30.days.from_now)
    end

    it "creates token without expiration" do
      token, _ = ApiToken.generate_for(user: user, organization: organization, name: "Test")
      expect(token.expires_at).to be_nil
    end

    it "returns unique plain tokens" do
      _, plain1 = ApiToken.generate_for(user: user, organization: organization, name: "Test1")
      _, plain2 = ApiToken.generate_for(user: user, organization: organization, name: "Test2")

      expect(plain1).not_to eq(plain2)
    end

    it "cannot be called without organization even with nil" do
      expect {
        ApiToken.generate_for(user: user, organization: nil, name: "Test")
      }.to raise_error(ActiveRecord::RecordInvalid, /Organization must exist/)
    end
  end

  describe ".find_by_token" do
    let!(:token) { ApiToken.generate_for(user: user, organization: organization, name: "Test").first }
    let!(:plain_token) { ApiToken.generate_for(user: user, organization: organization, name: "Test2").last }

    it "finds token by plain text and retains organization" do
      found = ApiToken.find_by_token(plain_token)
      expect(found).to be_present
      expect(found.organization_id).to eq(organization.id)
    end

    it "returns nil for invalid token" do
      expect(ApiToken.find_by_token("invalid")).to be_nil
    end

    it "returns nil for revoked token" do
      token.revoke!
      old_plain = Digest::SHA256.hexdigest("test")
      token.update_column(:token_digest, old_plain)

      expect(ApiToken.find_by_token("test")).to be_nil
    end

    it "returns nil for expired token" do
      token, plain = ApiToken.generate_for(
        user: user,
        organization: organization,
        name: "Expired",
        expires_in: -1.day
      )

      expect(ApiToken.find_by_token(plain)).to be_nil
    end
  end

  describe "scopes" do
    let!(:active_token) { ApiToken.generate_for(user: user, organization: organization, name: "Active").first }
    let!(:revoked_token) { ApiToken.generate_for(user: user, organization: organization, name: "Revoked").first }
    let!(:expired_token) { ApiToken.generate_for(user: user, organization: organization, name: "Expired", expires_in: -1.day).first }
    let!(:other_org_token) { ApiToken.generate_for(user: user, organization: other_org, name: "Other").first }

    before { revoked_token.revoke! }

    describe ".active" do
      it "includes active tokens" do
        expect(ApiToken.active).to include(active_token)
      end

      it "excludes revoked tokens" do
        expect(ApiToken.active).not_to include(revoked_token)
      end

      it "excludes expired tokens" do
        expect(ApiToken.active).not_to include(expired_token)
      end

      it "active tokens still have organization" do
        ApiToken.active.each do |token|
          expect(token.organization_id).to be_present
          expect(token.organization).to be_present
        end
      end
    end

    describe ".revoked" do
      it "includes revoked tokens" do
        expect(ApiToken.revoked).to include(revoked_token)
      end

      it "excludes active tokens" do
        expect(ApiToken.revoked).not_to include(active_token)
      end

      it "includes expired tokens that are also revoked" do
        expect(ApiToken.revoked).not_to include(expired_token)
      end

      it "revoked tokens have revoked_at timestamp" do
        ApiToken.revoked.each do |token|
          expect(token.revoked_at).to be_present
        end
      end
    end

    describe ".for_organization" do
      it "returns only tokens for specified organization" do
        tokens = ApiToken.for_organization(organization.id)
        expect(tokens).to include(active_token, revoked_token, expired_token)
        expect(tokens).not_to include(other_org_token)
      end

      it "returns tokens across all states for the organization" do
        tokens = ApiToken.for_organization(organization.id)
        expect(tokens.count).to eq(3)
      end

      it "works with chaining" do
        active_for_org = ApiToken.active.for_organization(organization.id)
        expect(active_for_org).to include(active_token)
        expect(active_for_org).not_to include(revoked_token, expired_token, other_org_token)
      end
    end
  end

  describe "instance methods" do
    let(:token) { ApiToken.generate_for(user: user, organization: organization, name: "Test", scopes: [ "read", "write" ]).first }

    describe "#has_scope?" do
      it "returns true for granted scope" do
        expect(token.has_scope?("read")).to be true
        expect(token.has_scope?("write")).to be true
      end

      it "returns false for non-granted scope" do
        expect(token.has_scope?("admin")).to be false
      end

      it "admin scope grants all scopes" do
        admin_token = ApiToken.generate_for(user: user, organization: organization, name: "Admin", scopes: [ "admin" ]).first
        expect(admin_token.has_scope?("read")).to be true
        expect(admin_token.has_scope?("write")).to be true
        expect(admin_token.has_scope?("admin")).to be true
      end
    end

    describe "#revoke!" do
      it "sets revoked to true" do
        expect { token.revoke! }.to change { token.revoked }.from(false).to(true)
      end

      it "sets revoked_at timestamp" do
        expect(token.revoked_at).to be_nil
        token.revoke!
        expect(token.revoked_at).to be_present
        expect(token.revoked_at).to be_within(1.second).of(Time.current)
      end

      it "keeps organization after revocation" do
        token.revoke!
        expect(token.organization_id).to eq(organization.id)
        expect(token.organization).to eq(organization)
      end

      it "makes token inactive" do
        token.revoke!
        expect(token.active?).to be false
      end
    end

    describe "#expired?" do
      it "returns false for non-expiring token" do
        expect(token.expired?).to be false
      end

      it "returns true for expired token" do
        expired = ApiToken.generate_for(user: user, organization: organization, name: "Exp", expires_in: -1.day).first
        expect(expired.expired?).to be true
      end

      it "expired tokens still have organization" do
        expired = ApiToken.generate_for(user: user, organization: organization, name: "Exp", expires_in: -1.day).first
        expect(expired.organization_id).to eq(organization.id)
      end
    end

    describe "#active?" do
      it "returns true for non-revoked, non-expired token" do
        expect(token.active?).to be true
      end

      it "returns false for revoked token" do
        token.revoke!
        expect(token.active?).to be false
      end

      it "returns false for expired token" do
        expired = ApiToken.generate_for(user: user, organization: organization, name: "Exp", expires_in: -1.day).first
        expect(expired.active?).to be false
      end
    end

    describe "#touch_last_used!" do
      it "updates last_used_at" do
        expect { token.touch_last_used! }.to change { token.reload.last_used_at }.from(nil)
      end

      it "keeps organization after touch" do
        token.touch_last_used!
        expect(token.reload.organization_id).to eq(organization.id)
      end
    end
  end

  describe "organization deletion cascade" do
    it "deletes tokens when organization is deleted" do
      token, _ = ApiToken.generate_for(user: user, organization: organization, name: "Test")

      expect { organization.destroy }.to change { ApiToken.count }.by(-1)
      expect(ApiToken.find_by(id: token.id)).to be_nil
    end
  end
end
