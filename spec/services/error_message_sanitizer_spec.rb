require "rails_helper"

# ErrorMessageSanitizer is the single canonical redactor. These specs assert
# that it applies the FULL UNION of the patterns that used to live divergently
# across the three concern-level sanitizers:
#
#   * SanitizesCredentialErrors (models)  — PEM, JSON secret fields
#     (escaped-quote aware), Bearer, bare JWTs
#   * SanitizesErrorMessage (jobs)        — Bearer, key=/token=/secret= kv,
#     PEM, file paths, query-string creds
#   * SanitizesApiErrors (controllers)    — same set as the jobs concern
#
RSpec.describe ErrorMessageSanitizer do
  describe ".sanitize" do
    it "returns nil for nil input (no truncation applied)" do
      expect(described_class.sanitize(nil)).to be_nil
    end

    it "extracts and sanitizes an exception's message" do
      err = StandardError.new("Bearer abc.def.ghi expired")
      expect(described_class.sanitize(err)).to include("Bearer [REDACTED]")
    end

    it "truncates to max_length when given" do
      result = described_class.sanitize("a" * 600, max_length: 500)
      expect(result.length).to eq(500)
    end

    it "does not truncate when max_length is nil" do
      result = described_class.sanitize("a" * 600)
      expect(result.length).to eq(600)
    end
  end

  describe ".redact" do
    subject(:redact) { ->(s) { described_class.redact(s) } }

    # --- PEM blocks (all three concerns) -------------------------------
    it "redacts PEM blocks (with space in the header)" do
      msg = "boom #{SpecCredentialFixtures.pem(label: "EC PRIVATE KEY", body: "SECRETBODY")}"
      result = redact.call(msg)
      expect(result).to include("[REDACTED_PEM]")
      expect(result).not_to include("SECRETBODY")
    end

    it "redacts PEM blocks with no space after BEGIN/END" do
      msg = "-----BEGINRSAPRIVATEKEY-----SECRETBODY-----ENDRSAPRIVATEKEY-----"
      result = redact.call(msg)
      expect(result).to include("[REDACTED_PEM]")
      expect(result).not_to include("SECRETBODY")
    end

    # --- JSON secret fields (credential concern unique) ----------------
    it "redacts JSON private_key fields" do
      msg = '{"private_key":"SECRETDATA","project_id":"ok"}'
      result = redact.call(msg)
      expect(result).to include('"private_key":"[REDACTED]"')
      expect(result).to include('"project_id":"ok"')
      expect(result).not_to include("SECRETDATA")
    end

    it "redacts JSON client_secret fields" do
      msg = '{"client_secret":"shhh-do-not-leak","other":"keep"}'
      result = redact.call(msg)
      expect(result).to include('"client_secret":"[REDACTED]"')
      expect(result).not_to include("shhh-do-not-leak")
    end

    it "redacts JSON values containing escaped double-quotes without leaving a tail" do
      msg = '{"private_key":"pre\"escaped\"tail","project_id":"ok"}'
      result = redact.call(msg)
      expect(result).to include('"private_key":"[REDACTED]"')
      expect(result).not_to include("tail")
      expect(result).to include('"project_id":"ok"')
    end

    it "redacts the full service_account_json field" do
      msg = '{"service_account_json":"{\"type\":\"service_account\",\"private_key\":\"SECRET\"}"}'
      result = redact.call(msg)
      expect(result).to include('"service_account_json":"[REDACTED]"')
      expect(result).not_to include("SECRET")
    end

    # --- Bearer tokens (all three) -------------------------------------
    it "redacts Bearer tokens" do
      result = redact.call("401 Unauthorized: Bearer abcdef.token.xyz failed")
      expect(result).to include("Bearer [REDACTED]")
      expect(result).not_to include("abcdef.token.xyz")
    end

    # --- Bare JWTs (credential concern unique) -------------------------
    it "redacts bare JWTs" do
      msg = "token: #{[ "eyJhbGciOiJFUzI1NiIs", "eyJpc3MiOiJ4In0", "abcdef" ].join(".")} invalid"
      result = redact.call(msg)
      expect(result).to include("[REDACTED_JWT]")
    end

    it "does not let the generic token= rule clobber an already-redacted JWT" do
      # Regression: "token: <jwt>" must end as "[REDACTED_JWT]", not be
      # collapsed to "token=[REDACTED]" by the looser kv rule running after.
      msg = "token: #{[ "eyJhbGciOiJFUzI1NiIs", "eyJpc3MiOiJ4In0", "abcdef" ].join(".")}"
      expect(redact.call(msg)).to include("[REDACTED_JWT]")
    end

    # --- Query-string credentials (jobs/api concerns unique) -----------
    it "redacts query-string credential params while keeping the param name" do
      result = redact.call("GET https://api.example.com/v1?api_key=SUPERSECRET&page=2")
      expect(result).to include("api_key=[REDACTED]")
      expect(result).not_to include("SUPERSECRET")
      expect(result).to include("page=2")
    end

    it "redacts query-string client_secret params" do
      result = redact.call("callback?client_secret=topsecret&state=ok")
      expect(result).to include("client_secret=[REDACTED]")
      expect(result).not_to include("topsecret")
    end

    # --- Generic key/token/secret kv forms (jobs/api concerns) ---------
    it "redacts bare key= forms" do
      expect(redact.call("key=abcdef")).to eq("key=[REDACTED]")
    end

    it "redacts bare token: forms" do
      expect(redact.call("token: abcdef")).to eq("token=[REDACTED]")
    end

    it "redacts bare secret= forms" do
      expect(redact.call("secret=topsecretvalue")).to eq("secret=[REDACTED]")
    end

    # --- File paths (jobs/api concerns unique) -------------------------
    it "redacts credential-bearing file paths" do
      %w[
        /etc/secrets/auth_key.p8
        /app/config/service_account.json
        /home/x/cert.pem
        /opt/app/key.p12
      ].each do |path|
        result = redact.call("could not read #{path} here")
        expect(result).to include("[path]"), "expected #{path} to be redacted"
        expect(result).not_to include(path)
      end
    end

    # --- Combined / defense-in-depth -----------------------------------
    it "redacts a message that mixes several secret forms" do
      msg = 'Bearer eyJhbGciOi.payload.sig failed loading /app/auth.p8 ' \
            'with {"private_key":"LEAK"} and ?token=ZZZ'
      result = redact.call(msg)
      expect(result).to include("Bearer [REDACTED]")
      expect(result).to include("[path]")
      expect(result).to include('"private_key":"[REDACTED]"')
      expect(result).not_to include("LEAK")
      expect(result).not_to include("ZZZ")
    end

    it "leaves a benign message unchanged" do
      msg = "App \"com.example.app\" not found on Google Play. Upload a build first."
      expect(redact.call(msg)).to eq(msg)
    end
  end
end
