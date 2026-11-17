module AppStoreConnect
  class CredentialValidator
    # Carries the structured validation trace so callers
    # (controller, audit log) can report and store WHY validation failed.
    class ValidationError < StandardError
      attr_reader :trace

      def initialize(message, trace: [])
        super(message)
        @trace = trace
      end
    end

    # Per-endpoint outcome recorded during validation. `outcome` is one of:
    #   :extracted   — endpoint returned 2xx and we got a Team ID from it
    #   :empty       — endpoint returned 2xx but no bundle prefix was available
    #   :denied      — endpoint returned 401/403 (key role/access doesn't grant this resource)
    #   :http_error  — endpoint returned another HTTP status (404/5xx/etc.) or network error
    Probe = Struct.new(:endpoint, :outcome, :status, :data_count, :error_class, :error_message, keyword_init: true)

    Result = Struct.new(:team_id, :sources, :raw_samples, :trace, keyword_init: true)

    def initialize(key_id:, issuer_id:, private_key:, timeout: 15)
      @credential = TempCredential.new(key_id: key_id, issuer_id: issuer_id, private_key: private_key)
      @timeout = timeout
    end

    def validate!
      begin
        client = Client.new(credential: @credential, timeout: @timeout)
        # Apple exposes seedId on bundleIds. Apps and certificates do not
        # expose a team relationship, and include=team is not a valid query.
        body = client.get("bundleIds", params: { limit: 1, "fields[bundleIds]" => "seedId" })
      rescue => e
        status = e.message.match(/\bHTTP\s+(\d{3})/)&.captures&.first&.to_i
        probe = Probe.new(
          endpoint: "bundleIds", outcome: [ 401, 403 ].include?(status) ? :denied : :http_error,
          status: status, error_class: e.class.name, error_message: sanitize(e.message)
        )
        fail_validation!(probe)
      end

      bundles = Array(body["data"])
      team_id = bundles.filter_map { |bundle| bundle.dig("attributes", "seedId").presence }.first
      probe = Probe.new(endpoint: "bundleIds", outcome: team_id ? :extracted : :empty,
        status: 200, data_count: bundles.size)
      fail_validation!(probe) unless team_id

      Result.new(team_id: team_id, sources: [ "bundleIds" ], raw_samples: [ body ], trace: [ probe ])
    end

    private

    def fail_validation!(probe)
      bits = [ probe.endpoint, probe.outcome ]
      bits << "status=#{probe.status}" if probe.status
      bits << "data_count=#{probe.data_count}" if probe.data_count
      bits << "err=#{probe.error_class}" if probe.error_class
      Rails.logger.warn("[ASC::CredentialValidator] validation failed — #{bits.join(':')}")
      raise ValidationError.new(failure_message(probe), trace: [ probe ])
    end

    # The controller surfaces this message as a flash alert.
    def failure_message(probe)
      if probe.error_message.to_s.match?(/agreement|contract/i)
        "Ask the Apple Account Holder to review and accept pending agreements in App Store Connect " \
        "or the Apple Developer account, then retry."
      elsif probe.status == 401
        "Apple could not authenticate your API key. Check the Key ID, Issuer ID, and .p8 private key, " \
        "and confirm the key has not been revoked."
      elsif probe.status == 403
        "Your API key does not have access to Bundle IDs. " \
        "Grant the key 'Access to Certificates, Identifiers and Profiles' in App Store Connect, " \
        "and check the team's account requirements."
      elsif probe.outcome == :empty && probe.data_count == 0
        "Apple returned no Bundle IDs for this key. " \
        "Register at least one Bundle ID in 'Certificates, Identifiers & Profiles', then retry."
      elsif probe.status == 429
        "Apple is rate limiting requests. Wait a few minutes, then retry."
      elsif probe.status.to_i >= 500 || probe.error_class.to_s.start_with?("Faraday::")
        "Could not reach Apple successfully. Please retry in a few minutes."
      else
        "Could not validate the Apple connection. Check the Key ID, Issuer ID, and .p8 private key, then retry."
      end
    end

    # Strip anything that could leak credential material before the message
    # lands in logs or AuditEvent metadata.
    def sanitize(msg)
      s = msg.to_s.dup
      s.gsub!(/-----BEGIN [^-]+-----.*?-----END [^-]+-----/m, "[REDACTED_PEM]")
      s.gsub!(/\bBearer\s+[A-Za-z0-9._~+\/=-]+/i, "Bearer [REDACTED]")
      s.gsub!(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, "[REDACTED_JWT]")
      s.truncate(500)
    end

    TempCredential = Struct.new(:key_id, :issuer_id, :private_key, keyword_init: true) do
      def active?
        true
      end
    end
  end
end
