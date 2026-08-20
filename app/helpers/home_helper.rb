module HomeHelper
  # Classifies a sync error_message into a one-line user-facing hint so
  # dashboard error cards can tell the user *what to do* rather than
  # just *what failed*. Matched on substrings so we don't have to keep a
  # rigid taxonomy in lockstep with every third-party API's wording.
  # Returns nil for unrecognized errors -- the card just shows the raw
  # message in that case, which is what we did before.
  def sync_error_hint(message)
    msg = message.to_s.downcase
    return "The sync worker died mid-run. Click Retry — this usually fixes it." if msg.include?("worker exited") || msg.include?("did not complete")
    return "Throttled by the upstream API. Wait a few minutes, then Retry." if msg.match?(/rate.?limit|throttl|\b429\b/)
    return "Your credentials look invalid or expired. Update them in Settings, then Retry." if msg.match?(/unauthorized|forbidden|invalid.*(?:key|token|credential)|expired|\b401\b|\b403\b/)
    return "Network hiccup. Click Retry; if it keeps failing, check status.mysigner.dev." if msg.match?(/timeout|timed out|connection refused|network|dns|ssl|tls|certificate/)

    nil
  end

  def sync_state(running:, credential:)
    last_status = credential&.last_sync_status

    label = if running
      "running"
    elsif last_status.present?
      last_status
    else
      "never"
    end

    badge_class = if running
      "badge-primary"
    elsif last_status == "ok"
      "badge-success"
    elsif last_status == "error"
      "badge-error"
    else
      "badge-ghost"
    end

    last_synced_at = credential&.last_synced_at

    {
      label: label,
      label_display: (label == "ok" ? "OK" : label.titleize),
      badge_class: badge_class,
      last_synced_at: last_synced_at,
      last_synced_phrase: last_synced_at.present? ? "#{time_ago_in_words(last_synced_at)} ago" : nil,
      last_error: credential&.last_sync_error
    }
  end

  def pending_setup_steps
    return [] unless @organization

    onboarded = current_user&.onboarding_completed?
    steps = []

    # CLI setup — only show if the user hasn't been through onboarding
    # (onboarding already walks them through installation)
    unless onboarded
      steps << {
        id: :cli_setup,
        title: "Install the CLI",
        description: "Get mysigner on your machine while you set up credentials",
        cta: "View Install Guide",
        path: "#",
        modal: "cli_setup_modal"
      }
    end

    # App Store Connect credentials
    unless @has_creds
      steps << {
        id: :asc_credentials,
        title: "Add App Store Connect Key",
        description: "Connect your Apple Developer account to manage certificates and deploy to TestFlight",
        cta: "Add API Key",
        path: organization_path(@organization, anchor: "asc-credentials")
      }
    end

    # API Token — only show if no token exists
    # (onboarding creates one, so this only appears if they somehow have none)
    unless @has_api_token
      steps << {
        id: :api_token,
        title: "Create API Token",
        description: "Generate a token so the CLI can authenticate with your organization",
        cta: "Create Token",
        path: new_organization_api_token_path(@organization)
      }
    end

    # Sync Apple data (only if has credentials but not synced)
    if @has_creds && @last_cred && @last_cred.last_sync_status != "ok"
      steps << {
        id: :asc_sync,
        title: "Sync Apple Data",
        description: "Pull your certificates, devices, and provisioning profiles",
        cta: "Sync Now",
        path: organization_path(@organization, anchor: "asc-credentials")
      }
    end

    # Google Play credentials (only if they don't have them yet)
    unless @android_has_creds
      steps << {
        id: :gp_credentials,
        title: "Add Google Play Credentials",
        description: "Connect Google Play Console to deploy Android apps",
        cta: "Add Service Account",
        path: organization_path(@organization, anchor: "gp-credentials")
      }
    end

    steps
  end

  def release_status_icon(platform)
    platform == :ios ? "fa-brands fa-apple" : "fa-brands fa-google-play"
  end

  def trend_arrow_html(direction)
    case direction
    when :up
      content_tag(:span, class: rating_trend_classes(:up)) do
        safe_join([
          content_tag(:i, "", class: "fa-solid fa-arrow-trend-up text-[0.65rem]"),
          content_tag(:span, "Up")
        ])
      end
    when :down
      content_tag(:span, class: rating_trend_classes(:down)) do
        safe_join([
          content_tag(:i, "", class: "fa-solid fa-arrow-trend-down text-[0.65rem]"),
          content_tag(:span, "Down")
        ])
      end
    else
      content_tag(:span, class: rating_trend_classes(:stable)) do
        safe_join([
          content_tag(:i, "", class: "fa-solid fa-minus text-[0.55rem]"),
          content_tag(:span, "Stable")
        ])
      end
    end
  end

  def expiry_banner_classes(days_remaining)
    return sn_error_classes if days_remaining.to_i <= 7
    sn_warning_classes
  end

  def expiry_icon_classes(days_remaining)
    return sn_icon_error_classes if days_remaining.to_i <= 7
    sn_icon_warning_classes
  end

  # Renders a compact percentage change badge: "+12.5%" in green or "-3.2%" in red
  def pct_change_html(value, invert: false)
    return "" if value.nil?
    direction = value > 0 ? :up : (value < 0 ? :down : :stable)
    direction = (direction == :up ? :down : :up) if invert && direction != :stable

    icon = case direction
    when :up then "fa-solid fa-arrow-trend-up"
    when :down then "fa-solid fa-arrow-trend-down"
    else "fa-solid fa-minus"
    end

    content_tag(:span, class: rating_trend_classes(direction)) do
      safe_join([
        content_tag(:i, "", class: "#{icon} text-[0.55rem]"),
        content_tag(:span, "#{value > 0 ? '+' : ''}#{value}%")
      ])
    end
  end
end
