require "rails_helper"

RSpec.describe AppStoreConnect::CredentialValidator do
  let(:valid_p8) do
    # Realistic-shape EC P-256 PEM; not a real Apple key. Used purely so the
    # Client's pre-flight `OpenSSL::PKey.read` doesn't reject the input before
    # we get to the stubbed HTTP layer.
    OpenSSL::PKey::EC.generate("prime256v1").to_pem
  end

  let(:validator) do
    described_class.new(
      key_id: "ABCD1234EF",
      issuer_id: "69a6de70-1234-5678-9012-3456789abcde",
      private_key: valid_p8,
      timeout: 1
    )
  end

  # Stub AppStoreConnect::Client so we don't hit Apple. Each test sets up
  # `client_get` to return a sequence of responses (one per fallback call).
  let(:fake_client) { instance_double(AppStoreConnect::Client) }
  before { allow(AppStoreConnect::Client).to receive(:new).and_return(fake_client) }

  describe "#validate! — happy paths" do
    it "extracts the team id from bundleIds via seedId on the first try" do
      allow(fake_client).to receive(:get).with("bundleIds", params: hash_including(:include)).and_return(
        { "data" => [ { "type" => "bundleIds", "attributes" => { "seedId" => "TEAM12345X" } } ] }
      )

      result = validator.validate!

      expect(result.team_id).to eq("TEAM12345X")
      expect(result.sources).to eq([ "bundleIds" ])
      expect(result.trace.size).to eq(1)
      expect(result.trace.first.outcome).to eq(:extracted)
      expect(result.trace.first.endpoint).to eq("bundleIds")
    end

    it "falls back to apps and reads the team relationship when bundleIds is denied" do
      allow(fake_client).to receive(:get).with("bundleIds", anything).and_raise(StandardError, "HTTP 403")
      allow(fake_client).to receive(:get).with("apps", params: hash_including(:include)).and_return(
        { "data" => [ { "type" => "apps", "relationships" => { "team" => { "data" => { "id" => "TEAMFROMAPP" } } } } ] }
      )

      result = validator.validate!

      expect(result.team_id).to eq("TEAMFROMAPP")
      expect(result.trace.map(&:endpoint)).to eq([ "bundleIds", "apps" ])
      expect(result.trace.map(&:outcome)).to eq([ :denied, :extracted ])
      expect(result.trace.first.status).to eq(403)
    end

    it "falls back to certificates as a last resort" do
      allow(fake_client).to receive(:get).with("bundleIds", anything).and_raise(StandardError, "HTTP 403")
      allow(fake_client).to receive(:get).with("apps", anything).and_return({ "data" => [] })
      allow(fake_client).to receive(:get).with("certificates", params: hash_including(:include)).and_return(
        { "data" => [ { "relationships" => { "team" => { "data" => { "id" => "TEAMFROMCERT" } } } } ] }
      )

      result = validator.validate!

      expect(result.team_id).to eq("TEAMFROMCERT")
      expect(result.trace.map(&:endpoint)).to eq([ "bundleIds", "apps", "certificates" ])
      expect(result.trace.map(&:outcome)).to eq([ :denied, :empty, :extracted ])
    end
  end

  describe "#validate! — failure modes (the whole point of this change)" do
    it "raises ValidationError with denied-on-all message when every endpoint is 403" do
      %w[bundleIds apps certificates].each do |endpoint|
        allow(fake_client).to receive(:get).with(endpoint, anything).and_raise(StandardError, "HTTP 403")
      end

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        expect(e.message).to match(/does not have access/i)
        expect(e.trace.size).to eq(3)
        expect(e.trace.map(&:outcome)).to eq([ :denied, :denied, :denied ])
        expect(e.trace.map(&:status)).to eq([ 403, 403, 403 ])
      end
    end

    it "raises ValidationError with empty-team message when every endpoint returns data:[]" do
      %w[bundleIds apps certificates].each do |endpoint|
        allow(fake_client).to receive(:get).with(endpoint, anything).and_return({ "data" => [] })
      end

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        expect(e.message).to match(/no Bundle IDs, Apps, or Certificates/i)
        expect(e.trace.map(&:outcome)).to eq([ :empty, :empty, :empty ])
        expect(e.trace.map(&:data_count)).to eq([ 0, 0, 0 ])
      end
    end

    it "raises ValidationError with mixed-outcome message when access is partial" do
      allow(fake_client).to receive(:get).with("bundleIds", anything).and_raise(StandardError, "HTTP 403")
      allow(fake_client).to receive(:get).with("apps", anything).and_return({ "data" => [] })
      allow(fake_client).to receive(:get).with("certificates", anything).and_raise(StandardError, "HTTP 403")

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        expect(e.message).to match(/denied access/i).and match(/no data/i)
        expect(e.trace.map(&:outcome)).to eq([ :denied, :empty, :denied ])
      end
    end

    it "classifies a 401 the same as a 403 (both are access denials)" do
      %w[bundleIds apps certificates].each do |endpoint|
        allow(fake_client).to receive(:get).with(endpoint, anything).and_raise(StandardError, "HTTP 401")
      end

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        expect(e.trace.map(&:outcome)).to all(eq(:denied))
        expect(e.trace.map(&:status)).to all(eq(401))
      end
    end

    it "classifies an Apple-body 'FORBIDDEN_ERROR' message as denied even without HTTP NNN in the text" do
      %w[bundleIds apps certificates].each do |endpoint|
        allow(fake_client).to receive(:get).with(endpoint, anything).and_raise(
          StandardError,
          "FORBIDDEN_ERROR: API key not authorized for this resource"
        )
      end

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        expect(e.trace.map(&:outcome)).to all(eq(:denied))
      end
    end

    it "classifies a 5xx as http_error (not denied, not empty)" do
      %w[bundleIds apps certificates].each do |endpoint|
        allow(fake_client).to receive(:get).with(endpoint, anything).and_raise(StandardError, "HTTP 503")
      end

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        expect(e.trace.map(&:outcome)).to all(eq(:http_error))
        expect(e.trace.map(&:status)).to all(eq(503))
      end
    end

    it "extracts the status from production-shaped Apple errors (HTTP NNN: title: detail)" do
      # AppStoreConnect::Client#parse! prepends "HTTP NNN: " to the error
      # message when Apple returns a structured errors[] body — which is the
      # common case for 403s. Spec ensures the trace's status field is
      # populated correctly for that shape, not just for the bare "HTTP NNN"
      # form. Regression guard for a real production gap.
      %w[bundleIds apps certificates].each do |endpoint|
        allow(fake_client).to receive(:get).with(endpoint, anything).and_raise(
          StandardError,
          "HTTP 403: FORBIDDEN_ERROR: This API key has no access to the requested resource"
        )
      end

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        expect(e.trace.map(&:status)).to eq([ 403, 403, 403 ])
        expect(e.trace.map(&:outcome)).to all(eq(:denied))
      end
    end

    it "classifies network errors (e.g. timeout) as http_error with nil status" do
      %w[bundleIds apps certificates].each do |endpoint|
        allow(fake_client).to receive(:get).with(endpoint, anything).and_raise(
          Faraday::TimeoutError, "execution expired"
        )
      end

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        expect(e.trace.map(&:outcome)).to all(eq(:http_error))
        expect(e.trace.map(&:status)).to all(be_nil)
        expect(e.trace.map(&:error_class)).to all(eq("Faraday::TimeoutError"))
      end
    end
  end

  describe "logging on terminal raise" do
    it "writes a single warn line summarizing all three probes" do
      allow(fake_client).to receive(:get).with("bundleIds", anything).and_raise(StandardError, "HTTP 403")
      allow(fake_client).to receive(:get).with("apps", anything).and_return({ "data" => [] })
      allow(fake_client).to receive(:get).with("certificates", anything).and_raise(StandardError, "HTTP 500")

      expect(Rails.logger).to receive(:warn).with(/ASC::CredentialValidator/).once.and_call_original

      expect { validator.validate! }.to raise_error(described_class::ValidationError)
    end

    it "includes endpoint:outcome:status fields in the log line for grep-ability" do
      %w[bundleIds apps certificates].each do |endpoint|
        allow(fake_client).to receive(:get).with(endpoint, anything).and_raise(StandardError, "HTTP 403")
      end

      logged = nil
      allow(Rails.logger).to receive(:warn) { |msg| logged = msg }

      expect { validator.validate! }.to raise_error(described_class::ValidationError)

      expect(logged).to include("bundleIds:denied:status=403")
      expect(logged).to include("apps:denied:status=403")
      expect(logged).to include("certificates:denied:status=403")
    end
  end

  describe "credential leak defenses" do
    it "does not echo PEM blocks from upstream errors into the trace's error_message" do
      pem_marker = "-----BEGIN PRIVATE KEY-----\nSECRETBODY\n-----END PRIVATE KEY-----"
      allow(fake_client).to receive(:get).with("bundleIds", anything).and_raise(
        StandardError,
        "Upstream returned: #{pem_marker} — please retry"
      )
      allow(fake_client).to receive(:get).with("apps", anything).and_return({ "data" => [] })
      allow(fake_client).to receive(:get).with("certificates", anything).and_return({ "data" => [] })

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        # The bundleIds probe's error_message must NOT contain the PEM body.
        bundle_probe = e.trace.find { |p| p.endpoint == "bundleIds" }
        expect(bundle_probe.error_message).to include("[REDACTED_PEM]")
        expect(bundle_probe.error_message).not_to include("SECRETBODY")
      end
    end

    it "does not echo Bearer tokens or JWTs into trace error_messages" do
      jwt_marker = "eyJhbGciOiJFUzI1NiIsImtpZCI6IkFCQ0RFRiJ9.eyJpc3MiOiJ4eHgifQ.signature"
      bearer_marker = "Bearer #{jwt_marker}"
      allow(fake_client).to receive(:get).with("bundleIds", anything).and_raise(
        StandardError,
        "auth header was: #{bearer_marker}"
      )
      allow(fake_client).to receive(:get).with("apps", anything).and_return({ "data" => [] })
      allow(fake_client).to receive(:get).with("certificates", anything).and_return({ "data" => [] })

      expect { validator.validate! }.to raise_error(described_class::ValidationError) do |e|
        bundle_probe = e.trace.find { |p| p.endpoint == "bundleIds" }
        # The bearer token's JWT body is the more dangerous part — make sure
        # neither the raw JWT nor the bearer-prefixed form survives.
        expect(bundle_probe.error_message).not_to include(jwt_marker)
        expect(bundle_probe.error_message).to include("[REDACTED")
      end
    end
  end

  describe "query parameters (the fix for atrid1995-style false negatives)" do
    it "requests `include=team` on apps so Apple populates relationships.team.data" do
      expect(fake_client).to receive(:get).with("bundleIds", anything).and_raise(StandardError, "HTTP 403")
      expect(fake_client).to receive(:get).with("apps", params: hash_including(include: "team")).and_return({ "data" => [] })
      expect(fake_client).to receive(:get).with("certificates", anything).and_return({ "data" => [] })

      expect { validator.validate! }.to raise_error(described_class::ValidationError)
    end

    it "requests `include=team` on certificates too" do
      expect(fake_client).to receive(:get).with("bundleIds", anything).and_raise(StandardError, "HTTP 403")
      expect(fake_client).to receive(:get).with("apps", anything).and_return({ "data" => [] })
      expect(fake_client).to receive(:get).with("certificates", params: hash_including(include: "team")).and_return({ "data" => [] })

      expect { validator.validate! }.to raise_error(described_class::ValidationError)
    end
  end
end
