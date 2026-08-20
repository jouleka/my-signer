module Audit
  # Centralized audit event logger. Called explicitly from controllers after
  # the business action succeeds. Never raises -- a failed audit write should
  # NOT break the user-visible operation.
  #
  # Usage:
  #   Audit::Logger.log(
  #     action: "member_invited",
  #     resource: @invitation,
  #     metadata: { email: @invitation.email, role: @invitation.role },
  #     request: request
  #   )
  #
  # When actor or organization is omitted, falls back to Current.user and
  # Current.organization respectively. Controller actions always have these
  # set via set_current_attributes, so explicit passing is optional.
  #
  # System / background-job events (L-19): pass `system_actor: true` for an
  # event initiated outside a request — e.g. a credential decrypt performed by
  # a background job. In that mode we do NOT fall back to Current.user (there
  # is no request actor), the actor stays nil (rendered as "System" by
  # AuditEvent#actor_display), and a `system_actor: true` breadcrumb is added
  # to the metadata so the row is distinguishable from a user-initiated one.
  #
  # Events are recorded for ALL organizations regardless of plan tier. The
  # Team-tier entitlement only gates VIEWING the audit log, not recording --
  # this ensures that if a Pro org upgrades to Team, their history is available.
  class Logger
    def self.log(action:, metadata: {}, resource: nil, actor: nil, organization: nil, request: nil, system_actor: false)
      new(
        action: action,
        metadata: metadata,
        resource: resource,
        actor: actor,
        organization: organization,
        request: request,
        system_actor: system_actor
      ).call
    end

    def initialize(action:, metadata:, resource:, actor:, organization:, request:, system_actor: false)
      @action = action.to_s
      @metadata = metadata.is_a?(Hash) ? metadata.compact : {}
      @resource = resource
      @system_actor = system_actor
      # For a system/background event there is no request actor to fall back to;
      # leaving @actor nil makes AuditEvent render it as "System". For normal
      # events, fall back to Current.user as before.
      @actor = if system_actor
        actor
      else
        actor || Current.user
      end
      @organization = organization || Current.organization
      # Tag system-initiated events so they're greppable/distinguishable from
      # the user-initiated path that shares the same action name.
      @metadata = @metadata.merge("system_actor" => true) if system_actor
      @request = request
    end

    def call
      unless AuditEvent::ACTIONS.include?(@action)
        # Surface typos in dev/test so a misspelled action doesn't silently
        # vanish. The early-return contract is unchanged -- callers still see
        # a no-op -- this just leaves a breadcrumb in the log.
        Rails.logger.warn("[Audit::Logger] Skipping unknown action: #{@action.inspect} (org=#{@organization&.id || 'nil'})")
        return
      end

      if @organization.nil?
        # Same rationale as above: nil organization usually means a controller
        # forgot to set Current.organization or pass it explicitly.
        Rails.logger.warn("[Audit::Logger] Skipping (#{@action}): organization is nil")
        return
      end

      AuditEvent.create!(
        organization: @organization,
        actor: @actor,
        action: @action,
        resource_type: @resource&.class&.name,
        resource_id: @resource&.id,
        metadata: @metadata,
        ip_address: truncated_ip,
        user_agent: truncated_user_agent,
        created_at: Time.current
      )
    rescue => e
      Rails.logger.error("[Audit::Logger] Failed to write audit event #{@action}: #{e.class} #{e.message}")
      nil
    end

    private

    # Truncate IPs for privacy. IPv4 -> /24 (e.g. 192.168.1.x). IPv6 -> /64
    # (keep the routing prefix, zero out the interface identifier). Uses
    # IPAddr for correct handling of zero-compression, IPv4-mapped addresses,
    # and loopback. Returns nil for missing/unparseable IPs.
    def truncated_ip
      raw = @request&.remote_ip
      return nil if raw.blank?

      require "ipaddr"
      addr = IPAddr.new(raw)

      if addr.ipv4?
        # Mask to /24 and replace last octet with "x" for consistency with the
        # prior behavior of ending in ".x".
        masked = addr.mask(24).to_s
        parts = masked.split(".")
        "#{parts[0..2].join(".")}.x"
      elsif addr.ipv6?
        addr.mask(64).to_s + "/64"
      else
        nil
      end
    rescue IPAddr::Error, ArgumentError
      nil
    end

    def truncated_user_agent
      @request&.user_agent&.to_s&.truncate(500)
    end
  end
end
