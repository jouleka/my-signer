require "rails_helper"
require "webmock/rspec"

RSpec.describe AppStoreConnect::CredentialValidator do
  let(:private_key) { OpenSSL::PKey::EC.generate("prime256v1").to_pem }
  let(:validator) do
    described_class.new(key_id: "ABCD1234EF", issuer_id: "69a6de70-1234-5678-9012-3456789abcde",
      private_key: private_key, timeout: 1)
  end
  let(:apple_request) do
    stub_request(:get, "https://api.appstoreconnect.apple.com/v1/bundleIds")
      .with(query: { "limit" => "1", "fields[bundleIds]" => "seedId" })
  end

  def apple_error(status, detail)
    apple_request.to_return(status: status, body: {
      errors: [ { title: "Apple API error", detail: detail } ]
    }.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "uses the documented bundleIds fields without unsupported team includes" do
    apple_request.to_return(status: 200, body: {
      data: [ { type: "bundleIds", id: "bundle-1", attributes: { seedId: "TEAM12345X" } } ]
    }.to_json)

    result = validator.validate!

    expect(result.team_id).to eq("TEAM12345X")
    expect(result.sources).to eq([ "bundleIds" ])
    expect(result.trace.sole.outcome).to eq(:extracted)
    expect(result.trace.sole.status).to eq(200)
    expect(apple_request).to have_been_requested.once
  end

  it "explains how to proceed when Apple returns no bundle IDs" do
    apple_request.to_return(status: 200, body: { data: [] }.to_json)

    expect { validator.validate! }.to raise_error(described_class::ValidationError) do |error|
      expect(error.message).to include("no Bundle IDs", "Register at least one")
      expect(error.trace.sole.outcome).to eq(:empty)
      expect(error.trace.sole.data_count).to eq(0)
    end
  end

  it "does not invent a team from an app ID or an undocumented relationship" do
    apple_request.to_return(status: 200, body: {
      data: [ { id: "BUNDLEID", relationships: { team: { data: { id: "NOT_A_DOCUMENTED_TEAM" } } } } ]
    }.to_json)

    expect { validator.validate! }.to raise_error(described_class::ValidationError) do |error|
      expect(error.trace.sole.outcome).to eq(:empty)
      expect(error.trace.sole.data_count).to eq(1)
    end
  end

  it "distinguishes authentication failure from missing permissions" do
    apple_error(401, "Authentication credentials are missing or invalid")

    expect { validator.validate! }.to raise_error(described_class::ValidationError) do |error|
      expect(error.message).to include("Key ID", "Issuer ID", "revoked")
      expect(error.trace.sole.status).to eq(401)
      expect(error.trace.sole.outcome).to eq(:denied)
    end
  end

  it "explains the required permission when Apple denies access" do
    apple_error(403, "This API key has no access to the requested resource")

    expect { validator.validate! }.to raise_error(described_class::ValidationError) do |error|
      expect(error.message).to include("does not have access to Bundle IDs", "Identifiers and Profiles")
      expect(error.trace.sole.status).to eq(403)
    end
  end

  it "directs agreement problems to the Account Holder" do
    apple_error(403, "A required agreement is missing or has expired.")

    expect { validator.validate! }.to raise_error(described_class::ValidationError) do |error|
      expect(error.message).to include("Account Holder", "agreements")
      expect(error.message).not_to include("regenerate")
    end
  end

  it "keeps an Apple service failure distinct from invalid credentials" do
    apple_error(503, "Service unavailable")

    expect { validator.validate! }.to raise_error(described_class::ValidationError) do |error|
      expect(error.message).to include("retry in a few minutes")
      expect(error.trace.sole.outcome).to eq(:http_error)
      expect(error.trace.sole.status).to eq(503)
    end
  end

  it "returns a validation error when a submitted key is blank" do
    validator = described_class.new(key_id: "", issuer_id: "issuer", private_key: private_key)

    expect { validator.validate! }.to raise_error(described_class::ValidationError, /Key ID/)
    expect(apple_request).not_to have_been_requested
  end

  it "returns a validation error when a submitted private key is malformed" do
    validator = described_class.new(key_id: "ABCD1234EF", issuer_id: "issuer", private_key: "not-a-key")

    expect { validator.validate! }.to raise_error(described_class::ValidationError, /private key/)
    expect(apple_request).not_to have_been_requested
  end

  it "logs endpoint, status and outcome once without credential material" do
    apple_error(403, "Access denied")
    expect(Rails.logger).to receive(:warn).with(
      "[ASC::CredentialValidator] validation failed — bundleIds:denied:status=403:err=StandardError"
    ).once

    expect { validator.validate! }.to raise_error(described_class::ValidationError)
  end

  it "redacts credential material before storing diagnostic errors" do
    jwt = "eyJhbGciOiJFUzI1NiJ9.eyJpc3MiOiJzZWNyZXQifQ.signature"
    apple_error(403, "#{private_key} Bearer #{jwt}")

    expect { validator.validate! }.to raise_error(described_class::ValidationError) do |error|
      message = error.trace.sole.error_message
      expect(message).to include("[REDACTED_PEM]", "[REDACTED]")
      expect(message).not_to include(private_key, jwt)
    end
  end
end
