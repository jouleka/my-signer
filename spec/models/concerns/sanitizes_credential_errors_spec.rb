require "rails_helper"

RSpec.describe SanitizesCredentialErrors do
  let(:dummy_class) do
    Class.new do
      include SanitizesCredentialErrors
    end
  end
  let(:dummy) { dummy_class.new }

  describe "#sanitize_error" do
    it "returns nil for nil input" do
      expect(dummy.send(:sanitize_error, nil)).to be_nil
    end

    it "redacts PEM blocks" do
      msg = "failed: -----BEGIN EC PRIVATE KEY-----\nABC\n-----END EC PRIVATE KEY-----"
      expect(dummy.send(:sanitize_error, msg)).to include("[REDACTED_PEM]")
      expect(dummy.send(:sanitize_error, msg)).not_to include("ABC")
    end

    it "redacts JSON secret fields" do
      msg = '{"private_key":"SECRETDATA","project_id":"ok"}'
      result = dummy.send(:sanitize_error, msg)
      expect(result).to include('"private_key":"[REDACTED]"')
      expect(result).to include('"project_id":"ok"')
      expect(result).not_to include("SECRETDATA")
    end

    it "redacts Bearer tokens" do
      msg = [ "401 Unauthorized: Bearer eyJhbGciOiJFUzI1NiIs", "abc", "def" ].join(".")
      expect(dummy.send(:sanitize_error, msg)).to include("Bearer [REDACTED]")
    end

    it "redacts bare JWTs" do
      msg = "token: #{[ "eyJhbGciOiJFUzI1NiIs", "eyJpc3MiOiJ4In0", "abcdef" ].join(".")}"
      expect(dummy.send(:sanitize_error, msg)).to include("[REDACTED_JWT]")
    end

    it "redacts JSON values that contain escaped double-quotes" do
      # Apple and Google both occasionally emit JSON where a string value
      # embeds escaped quotes — e.g. inlined PEM bodies or nested error
      # payloads. A naive `[^"]*` match terminates at the first escaped
      # quote and leaves the tail of the secret unredacted.
      msg = '{"private_key":"pre\"escaped\"tail","project_id":"ok"}'
      result = dummy.send(:sanitize_error, msg)
      expect(result).to include('"private_key":"[REDACTED]"')
      expect(result).not_to include("tail")
      expect(result).to include('"project_id":"ok"')
    end

    it "redacts the full service_account_json field" do
      msg = '{"service_account_json":"{\"type\":\"service_account\",\"private_key\":\"SECRET\"}"}'
      result = dummy.send(:sanitize_error, msg)
      expect(result).to include('"service_account_json":"[REDACTED]"')
      expect(result).not_to include("SECRET")
    end
  end
end
