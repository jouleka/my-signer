module AppStoreConnect
  class CredentialValidator
    # Carries the structured trace of all endpoints we tried so callers
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
    #   :empty       — endpoint returned 2xx but `data: []` or no Team ID extractable from the payload
    #   :denied      — endpoint returned 401/403 (key role/access doesn't grant this resource)
    #   :http_error  — endpoint returned another HTTP status (404/5xx/etc.) or network error
    Probe = Struct.new(:endpoint, :outcome, :status, :data_count, :error_class, :error_message, keyword_init: true)

    Result = Struct.new(:team_id, :sources, :raw_samples, :trace, keyword_init: true)

    def initialize(key_id:, issuer_id:, private_key:, timeout: 15)
      @credential = TempCredential.new(key_id: key_id, issuer_id: issuer_id, private_key: private_key)
      @timeout = timeout
    end

    def validate!
      client = Client.new(credential: @credential, timeout: @timeout)

      samples = []
      sources = []
      trace = []

      # Order: bundleIds first (most reliable — has seedId directly on every
      # bundle resource). apps + certificates request `include: "team"` so
      # Apple populates the team relationship in the response, which the
      # extractors below read.
      attempts = [
        [ "bundleIds",    { limit: 1, include: "profiles,team" }, :extract_team_id_from_bundle_ids ],
        [ "apps",         { limit: 1, include: "team" },          :extract_team_id_from_apps ],
        [ "certificates", { limit: 1, include: "team" },          :extract_team_id_from_certificates ]
      ]

      attempts.each do |endpoint, params, extractor|
        begin
          body = client.get(endpoint, params: params)
          samples << body
          sources << endpoint
          team_id = send(extractor, body)
          data_count = Array(body["data"]).size

          if team_id.present?
            trace << Probe.new(endpoint: endpoint, outcome: :extracted, status: 200, data_count: data_count)
            return Result.new(team_id: team_id, sources: sources, raw_samples: samples, trace: trace)
          else
            trace << Probe.new(endpoint: endpoint, outcome: :empty, status: 200, data_count: data_count)
          end
        rescue => e
          msg = e.message.to_s
          status = msg.match(/\bHTTP\s+(\d{3})/)&.captures&.first&.to_i
          outcome = case status
          when 401, 403 then :denied
          else
                      # Apple sometimes returns "FORBIDDEN_ERROR" or
                      # "NOT_AUTHORIZED" in the body without a stripped status.
                      # Treat those as :denied too.
                      msg.match?(/forbidden|not[_\s]authorized|unauthorized/i) ? :denied : :http_error
          end
          samples << { "error" => msg, "source" => endpoint }
          sources << "#{endpoint}:error"
          trace << Probe.new(
            endpoint: endpoint, outcome: outcome, status: status,
            error_class: e.class.name, error_message: sanitize(msg)
          )
        end
      end

      # All three attempts exhausted without an extractable Team ID.
      log_failure!(trace)
      raise ValidationError.new(failure_message(trace), trace: trace)
    end

    private

    # Build a single concise log line summarizing why each endpoint didn't
    # yield a Team ID. Goes to Rails.logger.warn so it shows up in the
    # standard production log stream without an explicit logger configured.
    # Sanitized: no PEM bodies, no JWTs, no bearer tokens (defense in depth —
    # Apple's error responses shouldn't include those but the validator must
    # never echo them even if a future SDK quirk drops them in).
    def log_failure!(trace)
      summary = trace.map do |probe|
        bits = [ probe.endpoint, probe.outcome ]
        bits << "status=#{probe.status}" if probe.status
        bits << "data_count=#{probe.data_count}" if probe.data_count
        bits << "err=#{probe.error_class}" if probe.error_class
        bits.join(":")
      end.join(" | ")
      Rails.logger.warn("[ASC::CredentialValidator] team_id not extractable — #{summary}")
    end

    # Construct a user-actionable error message based on what we saw. Falls
    # back to the original generic copy if the trace doesn't match a known
    # signature. The controller will surface this as a flash alert.
    def failure_message(trace)
      denied_endpoints = trace.select { |p| p.outcome == :denied }.map(&:endpoint)
      empty_endpoints  = trace.select { |p| p.outcome == :empty  }.map(&:endpoint)

      if denied_endpoints.size == trace.size
        "Your API key does not have access to Bundle IDs, Apps, or Certificates. " \
        "Grant the key 'Access to Certificates, Identifiers and Profiles' in App Store Connect, " \
        "or regenerate it under a role with broader access (e.g. Admin)."
      elsif empty_endpoints.size == trace.size
        "Your Apple Developer team has no Bundle IDs, Apps, or Certificates yet. " \
        "Register at least one Bundle ID in 'Certificates, Identifiers & Profiles', then retry."
      elsif denied_endpoints.any? && empty_endpoints.any?
        "Your API key was denied access to some resources (#{denied_endpoints.join(', ')}) " \
        "and returned no data on others (#{empty_endpoints.join(', ')}). Check the key's role " \
        "and team selection in App Store Connect."
      else
        "Could not extract Team ID from Apple API. Please ensure your API key has proper access to Apps, Bundle IDs, or Certificates."
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

    def extract_team_id_from_apps(body)
      extract_team_id(body) do |item|
        [
          item.dig("relationships", "team", "data", "id"),
          extract_from_url(item.dig("relationships", "team", "links", "related"))
        ]
      end
    end

    def extract_team_id_from_bundle_ids(body)
      extract_team_id(body) do |item|
        [
          item.dig("attributes", "seedId"), # The seedId IS the Team ID!
          item.dig("relationships", "team", "data", "id"),
          extract_from_url(item.dig("relationships", "team", "links", "related"))
        ]
      end
    end

    def extract_team_id_from_certificates(body)
      extract_team_id(body) do |item|
        [
          item.dig("relationships", "team", "data", "id"),
          extract_from_url(item.dig("relationships", "team", "links", "related"))
        ]
      end
    end

    def extract_team_id(body)
      return if body.blank?

      Array(body["data"]).each do |item|
        Array(yield(item)).each do |candidate|
          return candidate if candidate.present?
        end
      end

      Array(body["included"]).each do |included_item|
        candidate = included_item.dig("attributes", "teamId") || included_item.dig("attributes", "teamIdentifier")
        return candidate if candidate.present?
      end

      nil
    end

    def extract_from_url(url)
      return if url.blank?
      url.match(%r{/teams/([^/?]+)})&.captures&.first
    end
  end
end
