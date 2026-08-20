require "openssl"
require "jwt"
require "faraday"
require "faraday/retry"
require "json"
require "ipaddr"

module AppStoreConnect
  class Client
    API_BASE = "https://api.appstoreconnect.apple.com".freeze
    V1 = "/v1".freeze

    def initialize(credential:, timeout: 20)
      @credential = credential
      validate_credential!
      @conn = Faraday.new(url: API_BASE) do |f|
        f.request :retry, max: 4, interval: 0.4, interval_randomness: 0.2, backoff_factor: 2,
                           retry_statuses: [ 429, 500, 502, 503, 504 ], methods: %i[get post patch delete]
        f.options.timeout = timeout
        # Persistent connections across the many sequential requests a sync
        # makes. Falls back to the default adapter in environments (e.g. specs
        # that stub the HTTP layer without this gem) where it's unavailable.
        begin
          f.adapter :net_http_persistent, pool_size: 4
        rescue Faraday::AdapterNotFound, LoadError, NameError
          f.adapter Faraday.default_adapter
        end
      end
    end

    def get(path, params: {})
      request(:get, path, params: params)
    end

    def post(path, json: {})
      request(:post, path, json: json)
    end

    def patch(path, json: {})
      request(:patch, path, json: json)
    end

    def delete(path)
      request(:delete, path)
    end

    # DELETE with a JSON request body (used by Apple's relationship unlinking endpoints)
    def delete_with_body(path, json: {})
      request(:delete, path, json: json)
    end

    def put_binary(url:, data:, content_type:, headers: {})
      uri = URI.parse(url)
      # Resolve + validate ONCE, then pin the exact validated IP for the actual
      # connection (L-10). Previously the validated host was re-resolved by
      # Faraday/Net::HTTP at connect time — a TOCTOU window where a DNS-rebinding
      # attacker could flip the host to a private/internal address between the
      # check and the connect. We now connect to the pinned IP while keeping the
      # original hostname for TLS SNI + certificate hostname verification.
      pinned_ip = validate_external_url!(uri)
      conn = Faraday.new(url: "#{uri.scheme}://#{uri.host}") do |f|
        f.request :retry, max: 3, interval: 0.5, backoff_factor: 2,
                           retry_statuses: [ 429, 500, 502, 503, 504 ], methods: %i[put]
        f.options.timeout = 120
        # :net_http is Faraday's default adapter; pin the destination IP via the
        # adapter config block (Net::HTTP#ipaddr) so the socket connects to the
        # validated address and cannot be re-resolved to a different one.
        f.adapter :net_http do |http|
          http.ipaddr = pinned_ip if pinned_ip
        end
      end

      resp = conn.put(uri.request_uri) do |r|
        r.headers["Content-Type"] = content_type
        headers.each { |k, v| r.headers[k] = v }
        r.body = data
      end

      raise StandardError, "Binary upload failed: HTTP #{resp.status}" unless (200..299).include?(resp.status.to_i)
      resp
    end

    def paginate(path, params: {})
      url = path
      q = params.dup
      loop do
        body = get(url, params: q)
        yield body if block_given?
        next_link = body.dig("links", "next")
        break unless next_link
        uri = URI.parse(next_link)
        url = uri.path.sub(V1 + "/", "")
        q = URI.decode_www_form(uri.query.to_s).to_h
      end
    end

    private

    def request(method, path, params: nil, json: nil)
      headers = { "Authorization" => "Bearer #{jwt}", "Accept" => "application/json" }
      headers["Content-Type"] = "application/json" if json
      resp = @conn.send(method) do |r|
        r.url(full_path(path))
        r.headers.update(headers)
        r.params.update(params) if params
        r.body = JSON.dump(json) if json
      end
      parse!(resp)
    end

    def parse!(resp)
      status = resp.status.to_i
      body = begin
        resp.body.present? ? JSON.parse(resp.body) : {}
      rescue JSON::ParserError
        { "raw" => resp.body }
      end
      return body if (200..299).include?(status)

      # Collect all error messages from Apple. Both branches prefix the HTTP
      # status so downstream consumers (CredentialValidator's trace classifier,
      # log greps, audit metadata) can extract it reliably from the message.
      errors = body["errors"]
      if errors&.any?
        error_messages = errors.map do |err|
          detail = err["detail"]
          title = err["title"]
          [ title, detail ].compact.join(": ")
        end
        raise StandardError, "HTTP #{status}: #{error_messages.join('; ')}"
      else
        raise StandardError, "HTTP #{status}"
      end
    end

    def full_path(path)
      return path if path.start_with?("/v1/")
      "#{V1}/#{path}".gsub(%r{//+}, "/")
    end

    # Delegate to the single ES256 signer (M-10). JwtMinter owns caching, TTL,
    # the EC-key guard, AND emits the 'asc_credential_used' audit event on each
    # cache miss — so every Apple API call routed through #request is audited.
    # Previously this method had its OWN inline signer + per-instance cache,
    # which left the dominant request path unaudited and duplicated the signing
    # logic. The cross-request Rails.cache layer in JwtMinter also subsumes the
    # old per-instance @jwt_token memoization (and survives between client
    # instances within the cache window).
    def jwt
      JwtMinter.for(@credential)
    end

    def validate_credential!
      %i[key_id issuer_id private_key].each do |a|
        v = @credential.public_send(a)
        raise "Missing credential #{a}" if v.blank?
      end
      raise "Credential inactive" if @credential.respond_to?(:active?) && !@credential.active?
    end

    # Validates that an external URL is safe to request (HTTPS, no private IPs)
    # and returns the validated IP to pin the connection to (L-10 TOCTOU fix).
    # Prevents SSRF if an API response supplies a tampered upload/download URL.
    #
    # Resolves ONCE here. ALL resolved addresses must be public — if any maps to
    # a private/loopback/link-local range we reject (defends against a rebinding
    # record set that mixes a public and a private answer). The first validated
    # address is returned so the caller connects to exactly that IP rather than
    # re-resolving (which could yield a different, attacker-controlled address).
    def validate_external_url!(uri)
      raise "Unsafe URL scheme: #{uri.scheme}" unless uri.scheme == "https"

      begin
        addrs = Addrinfo.getaddrinfo(uri.host, nil, :UNSPEC, :STREAM)
        validated = nil
        addrs.each do |addr|
          ip = IPAddr.new(addr.ip_address)
          if ip.loopback? || ip.private? || ip.link_local?
            raise "Unsafe URL target: #{uri.host} resolves to private address"
          end
          validated ||= addr.ip_address
        end
        raise "Cannot resolve host: #{uri.host}" if validated.nil?
        validated
      rescue SocketError
        raise "Cannot resolve host: #{uri.host}"
      end
    end
  end
end
