module ApplicationHelper
  # Returns MySigner's AWS account ID (12-digit string) for display in the
  # BYOK setup panel. Looks at ENV["MYSIGNER_AWS_ACCOUNT_ID"] first; falls
  # back to parsing the account-id slot out of MYSIGNER_KMS_KEY_ARN, whose
  # format is `arn:aws:kms:<region>:<account_id>:key/<uuid>` (Epic 1 already
  # surfaces this ARN to the app; the account is the 5th colon-separated
  # field). Returns nil when neither source is available — the BYOK view
  # falls back to a "contact support" message in that case.
  def mysigner_aws_account_id
    explicit = ENV["MYSIGNER_AWS_ACCOUNT_ID"].to_s.strip
    return explicit if explicit.match?(/\A\d{12}\z/)

    arn = ENV["MYSIGNER_KMS_KEY_ARN"].to_s
    md  = arn.match(%r{\Aarn:aws:kms:[a-z0-9\-]+:(\d{12}):key/})
    md && md[1]
  end

  def mask_middle(value, show_start: 4, show_end: 4, mask: "••••")
    s = value.to_s
    return s if s.length <= (show_start + show_end)
    "#{s.first(show_start)}#{mask}#{s.last(show_end)}"
  end

  # Masks the local part of an email so the full address isn't shoulder-
  # surfable / browser-history-exposable on pages that the user reaches
  # via a URL-bound token (e.g. account restoration). Domain stays
  # visible so the user can recognize their own account; local part is
  # collapsed to first + ••• + last when long enough, or just first +
  # ••• for short locals. Returns the input unchanged if it doesn't
  # look like an email.
  def mask_email(email)
    s = email.to_s
    local, domain = s.split("@", 2)
    return s if local.blank? || domain.blank?

    masked_local =
      case local.length
      when 1 then local
      when 2 then "#{local[0]}•••"
      else        "#{local[0]}•••#{local[-1]}"
      end

    "#{masked_local}@#{domain}"
  end

  def expiry_badge(date)
    return tag.span("No Date", class: "badge badge-ghost") if date.blank?

    days_remaining = (date.to_date - Date.current).to_i

    if days_remaining <= 0
      tag.span("Expired", class: "badge badge-error text-white")
    elsif days_remaining < 7
      tag.span("#{days_remaining} days", class: "badge badge-error text-white")
    elsif days_remaining < 30
      tag.span("#{days_remaining} days", class: "badge badge-warning")
    else
      tag.span("#{days_remaining} days", class: "badge badge-success text-white")
    end
  end

  def breadcrumbs(items, tabs: nil)
    render partial: "shared/breadcrumbs", locals: { items:, tabs: }
  end

  def developer_navigation(current_organization:)
    org_present = current_organization.present?

    # iOS quick-create and shortcut items (kept for command palette)
    ios_quick_items = [
      {
        label: "Register Device",
        icon: "fa-solid fa-plus",
        path: (organization_apple_devices_path(current_organization, register: 1) if org_present),
        disabled: !org_present,
        requires_org: true,
        quick_create: true,
        show_in_sidebar: false,
        hint: "Register a new iOS device for development testing"
      },
      {
        label: "Create Profile",
        icon: "fa-solid fa-wand-magic-sparkles",
        path: (new_organization_apple_provisioning_profile_path(current_organization) if org_present),
        disabled: !org_present,
        requires_org: true,
        quick_create: true,
        show_in_sidebar: false,
        hint: "Create a new iOS provisioning profile"
      },
      {
        label: "Export Devices CSV",
        icon: "fa-solid fa-file-arrow-down",
        path: (organization_apple_devices_path(current_organization, format: :csv) if org_present),
        disabled: !org_present,
        requires_org: true,
        shortcut: true,
        show_in_sidebar: false,
        data: { turbo: false },
        hint: "Download all registered devices as a CSV file"
      }
    ]

    # Android quick-create items (kept for command palette)
    android_quick_items = [
      {
        label: "Upload Keystore",
        icon: "fa-solid fa-upload",
        path: (new_organization_android_keystore_path(current_organization) if org_present),
        disabled: !org_present,
        requires_org: true,
        quick_create: true,
        show_in_sidebar: false,
        hint: "Upload a new Android keystore for app signing"
      }
    ]

    [
      # ── OVERVIEW ──────────────────────────────────────────────
      {
        title: "Overview",
        items: [
          {
            label: "Dashboard",
            icon: "fa-solid fa-gauge-high",
            path: authenticated_root_path,
            shortcut: true,
            hint: "Overview of your apps, certificates, and signing status"
          }
        ]
      },

      # ── SHIP ──────────────────────────────────────────────────
      # Everything needed to get a release into the stores: assets,
      # screenshots, and the release pipeline itself.
      {
        title: "Ship",
        items: [
          {
            label: "Screenshot Studio",
            icon: "fa-solid fa-images",
            path: (organization_screenshot_projects_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            shortcut: true,
            hint: "Generate App Store and Play Store screenshots"
          },
          {
            label: "New Screenshot Project",
            icon: "fa-solid fa-plus",
            path: (new_organization_screenshot_project_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            quick_create: true,
            show_in_sidebar: false,
            hint: "Create a new screenshot project"
          },
          {
            label: "Releases",
            icon: "fa-solid fa-rocket",
            path: (organization_releases_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            hint: "Manage releases: store metadata, release notes, builds, and push to stores",
            count_badge: (org_present && current_organization.supports_review_workflow? ? current_organization.release_notes.where(status: "pending_review").count : 0)
          },
          {
            label: "Signing & Assets",
            icon: "fa-solid fa-shield-halved",
            path: (organization_signing_assets_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            shortcut: true,
            hint: "Certificates, profiles, keystores, and all signing assets"
          },
          # iOS + Android quick-creates stay reachable from the command palette.
          *ios_quick_items,
          *android_quick_items
        ]
      },

      # ── GROW ──────────────────────────────────────────────────
      # Free users can view these pages; editing/advanced features are
      # gated by entitlements on the controllers themselves.
      {
        title: "Grow",
        items: [
          {
            label: "Keywords & ASO",
            icon: "fa-solid fa-magnifying-glass-chart",
            path: (organization_keywords_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            hint: "Keyword management, suggestions, and ranking tracking"
          },
          {
            label: "Reviews & Ratings",
            icon: "fa-solid fa-star-half-stroke",
            path: (organization_reviews_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            hint: "Monitor reviews from both stores in one feed"
          },
          {
            label: "Analytics",
            icon: "fa-solid fa-chart-line",
            path: (organization_analytics_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            hint: "Acquisition, engagement, and quality metrics"
          },
          {
            label: "Custom Product Pages",
            icon: "fa-solid fa-palette",
            path: (organization_custom_product_pages_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            hint: "Create and manage Custom Product Pages for your iOS apps"
          }
        ]
      },

      # ── DEVELOPER ─────────────────────────────────────────────
      {
        title: "Developer",
        items: [
          {
            label: "API Tokens",
            icon: "fa-solid fa-key",
            path: (organization_api_tokens_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            shortcut: true,
            hint: "Manage API tokens for CLI and automation"
          },
          {
            label: "Create API Token",
            icon: "fa-solid fa-key",
            path: (new_organization_api_token_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            quick_create: true,
            show_in_sidebar: false,
            hint: "Generate a new API token for CLI authentication"
          }
        ],
        groups: [
          {
            label: "CLI & Docs",
            icon: "fa-solid fa-terminal",
            hint: "Command-line tools and documentation",
            items: [
              { label: "Quickstart", icon: "fa-solid fa-bolt", path: page_docs_path("quickstart", "getting-started"), hint: "Get started with MySigner CLI in 5 minutes" },
              { label: "Commands", icon: "fa-solid fa-list-check", path: category_docs_path("commands"), hint: "Full CLI command reference and examples" },
              { label: "Guides", icon: "fa-solid fa-route", path: category_docs_path("guides"), hint: "Step-by-step guides for CI/CD integration" },
              { label: "Dashboard", icon: "fa-solid fa-gauge-high", path: category_docs_path("dashboard"), hint: "Web dashboard documentation and features" }
            ]
          }
        ]
      },

      # ── ORGANIZATION ──────────────────────────────────────────
      # Org-level admin. Personal settings + logout live in the avatar
      # dropdown; no need to duplicate them here.
      {
        title: "Organization",
        items: [
          {
            label: "Organizations",
            icon: "fa-solid fa-building",
            path: organizations_path,
            shortcut: true,
            hint: "View and manage all your organizations"
          },
          {
            label: "New Organization",
            icon: "fa-solid fa-square-plus",
            path: new_organization_path,
            quick_create: true,
            show_in_sidebar: false,
            hint: "Create a new organization to manage apps and team members"
          },
          {
            label: "Invite Member",
            icon: "fa-solid fa-user-plus",
            path: (organization_path(current_organization, anchor: "invite") if org_present),
            disabled: !org_present,
            requires_org: true,
            quick_create: true,
            show_in_sidebar: false,
            hint: "Invite a new team member to your organization"
          },
          {
            label: "Plans & Billing",
            icon: "fa-solid fa-crown",
            path: pricing_path,
            hint: "See plan limits, features, and upgrade options"
          },
          # Team-tier admin. Surfaced for discoverability; controllers
          # enforce the actual plan/role gate.
          {
            label: "SSO",
            icon: "fa-solid fa-id-card-clip",
            path: (organization_sso_configuration_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            badge: "Team",
            hint: "SAML 2.0 Single Sign-On with your identity provider"
          },
          {
            label: "Audit Log",
            icon: "fa-solid fa-shield-halved",
            path: (organization_audit_events_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            badge: "Team",
            hint: "Track sensitive actions across your organization"
          },
          {
            label: "Permissions",
            icon: "fa-solid fa-key",
            path: (organization_permissions_path(current_organization) if org_present),
            disabled: !org_present,
            requires_org: true,
            badge: "Team",
            hint: "Role-based access control matrix for your team"
          }
        ]
      }
    ]
  end

  def navigation_shortcuts(nav_tree)
    flatten_navigation(nav_tree).select { |item| item[:shortcut] }
  end

  def navigation_quick_creates(nav_tree)
    flatten_navigation(nav_tree).select { |item| item[:quick_create] }
  end

  def sidebar_navigation(nav_tree)
    filter_navigation(nav_tree) { |item| item[:show_in_sidebar] != false }
  end

  def template_preview_bg(settings)
    case settings["background_type"]
    when "gradient"
      start_color = safe_css_color(settings["gradient_start"], "#000000")
      end_color = safe_css_color(settings["gradient_end"], "#764BA2")
      direction = settings["gradient_direction"] == "to-right" ? "to right" : "to bottom"
      "linear-gradient(#{direction}, #{start_color}, #{end_color})"
    when "mesh"
      mesh_preview_bg(settings)
    when "pattern"
      safe_css_color(settings["pattern_bg_color"], "#000000")
    when "image"
      "#000000"
    else
      safe_css_color(settings["background_color"], "#000000")
    end
  end

  # Whitelist user-supplied color values before interpolating them into inline
  # CSS. Only plain hex colors (#rgb/#rrggbb/#rrggbbaa) and a conservative set
  # of CSS named colors are accepted; anything else (including attempts to
  # inject extra declarations or `url(...)`/expressions) falls back to the
  # provided default. This keeps the helper's behavior unchanged for legitimate
  # color inputs while preventing CSS injection.
  CSS_HEX_COLOR = /\A#(?:\h{3}|\h{4}|\h{6}|\h{8})\z/
  CSS_NAMED_COLORS = %w[
    transparent currentcolor black white red green blue yellow orange purple
    gray grey silver maroon olive lime aqua teal navy fuchsia
  ].freeze

  def safe_css_color(value, default)
    return default if value.blank?

    candidate = value.to_s.strip
    if candidate.match?(CSS_HEX_COLOR) || CSS_NAMED_COLORS.include?(candidate.downcase)
      candidate
    else
      default
    end
  end

  MESH_PREVIEW_CSS = {
    "sunset" => "radial-gradient(circle 120% at 20% 30%, #FF6B35, transparent), radial-gradient(circle 100% at 70% 20%, #F7931E, transparent), radial-gradient(circle 110% at 50% 80%, #D4145A, transparent), #1a0533",
    "ocean" => "radial-gradient(circle 120% at 30% 20%, #0077B6, transparent), radial-gradient(circle 110% at 70% 50%, #00B4D8, transparent), radial-gradient(circle 100% at 20% 70%, #023E8A, transparent), #0a1628",
    "aurora" => "radial-gradient(circle 120% at 20% 40%, #00C9A7, transparent), radial-gradient(circle 100% at 60% 20%, #845EC2, transparent), radial-gradient(circle 110% at 80% 70%, #00B8A9, transparent), #0B0B1A",
    "lavender" => "radial-gradient(circle 120% at 30% 30%, #9B59B6, transparent), radial-gradient(circle 100% at 70% 20%, #8E44AD, transparent), radial-gradient(circle 110% at 50% 70%, #D4A5FF, transparent), #1A1025",
    "coral" => "radial-gradient(circle 120% at 30% 30%, #FF6F61, transparent), radial-gradient(circle 100% at 70% 50%, #FF9671, transparent), radial-gradient(circle 110% at 50% 80%, #FFC75F, transparent), #1A0A0A",
    "forest" => "radial-gradient(circle 120% at 30% 30%, #2D6A4F, transparent), radial-gradient(circle 100% at 70% 20%, #40916C, transparent), radial-gradient(circle 110% at 50% 70%, #52B788, transparent), #0A1A0A",
    "candy" => "radial-gradient(circle 120% at 20% 30%, #FF6B9D, transparent), radial-gradient(circle 100% at 70% 20%, #C44DFF, transparent), radial-gradient(circle 110% at 50% 80%, #FF85A1, transparent), #1A0820",
    "midnight" => "radial-gradient(circle 120% at 30% 30%, #1A1A4E, transparent), radial-gradient(circle 100% at 70% 20%, #2D2D7F, transparent), radial-gradient(circle 110% at 50% 70%, #15154B, transparent), #050510",
    "neon" => "radial-gradient(circle 110% at 20% 30%, #00FF87, transparent), radial-gradient(circle 100% at 70% 20%, #FF00E5, transparent), radial-gradient(circle 110% at 50% 80%, #00D4FF, transparent), #0A0A0A",
    "peach" => "radial-gradient(circle 120% at 30% 30%, #FFBE76, transparent), radial-gradient(circle 100% at 70% 20%, #FF9F43, transparent), radial-gradient(circle 110% at 50% 70%, #FECA57, transparent), #1A1008",
    "arctic" => "radial-gradient(circle 120% at 30% 30%, #74B9FF, transparent), radial-gradient(circle 100% at 70% 20%, #A29BFE, transparent), radial-gradient(circle 110% at 50% 70%, #81ECEC, transparent), #0A1520",
    "ember" => "radial-gradient(circle 120% at 20% 30%, #E74C3C, transparent), radial-gradient(circle 100% at 70% 20%, #E67E22, transparent), radial-gradient(circle 110% at 50% 80%, #C0392B, transparent), #1A0800"
  }.freeze

  def mesh_preview_bg(settings)
    preset = settings["mesh_preset"] || "sunset"
    MESH_PREVIEW_CSS[preset] || MESH_PREVIEW_CSS["sunset"]
  end

  private

  def flatten_navigation(nav_tree)
    nav_tree.flat_map do |section|
      section_items = Array(section[:items]).map do |item|
        item.merge(section: section[:title])
      end

      group_items = Array(section[:groups]).flat_map do |group|
        Array(group[:items]).map do |item|
          item.merge(section: section[:title], group: group[:label])
        end
      end

      section_items + group_items
    end
  end

  def filter_navigation(nav_tree)
    nav_tree.map do |section|
      section_items = Array(section[:items]).select { |item| yield(item) }
      section_groups = Array(section[:groups]).filter_map do |group|
        filtered = Array(group[:items]).select { |item| yield(item) }
        next if filtered.empty?

        group.merge(items: filtered)
      end

      next if section_items.blank? && section_groups.blank?

      section.merge(items: section_items.presence, groups: section_groups.presence)
    end.compact
  end
end
