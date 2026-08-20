require "rails_helper"

RSpec.describe AuditEventsController, type: :request do
  let(:owner) do
    User.create!(
      email: "owner@example.com",
      password: "SecurePassword123!",
      confirmed_at: Time.current,
      plan_tier: :team
    )
  end
  let(:organization) { Organization.create!(name: "Audit Team Org", owner: owner) }

  before do
    sign_in owner
    AuditEvent.create!(
      organization: organization,
      actor: owner,
      action: "member_invited",
      metadata: { email: "invitee@example.com", role: "developer" },
      created_at: 1.hour.ago
    )
    AuditEvent.create!(
      organization: organization,
      actor: owner,
      action: "api_token_created",
      metadata: { name: "CI Token" },
      created_at: 30.minutes.ago
    )
  end

  describe "GET /organizations/:organization_id/audit_logs" do
    it "renders audit events for a team-tier org owner" do
      get organization_audit_events_path(organization)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Audit Log")
      expect(response.body).to include("Member invited")
      expect(response.body).to include("Api token created")
    end

    it "filters by action" do
      get organization_audit_events_path(organization, action_filter: "member_invited")

      expect(response).to have_http_status(:ok)
      # In the filtered result table, only the invited row should appear.
      # The action dropdown will contain both labels as options, so we assert
      # on the CSV output for a cleaner filter check.
      get organization_audit_events_path(organization, action_filter: "member_invited", format: :csv)
      expect(response.body).to include("member_invited")
      expect(response.body).not_to include("api_token_created")
    end

    it "exports CSV" do
      get organization_audit_events_path(organization, format: :csv)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("Time (UTC)")
      expect(response.body).to include("member_invited")
      expect(response.headers["Content-Disposition"]).to include("audit_log_")
    end

    context "when the org is on Pro plan (not Team)" do
      before do
        owner.update!(plan_tier: :pro)
      end

      it "renders the Team-feature paywall page with an upgrade CTA" do
        get organization_audit_events_path(organization)

        # Friendly upgrade page instead of a generic Pundit denial.
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Audit Log")
        expect(response.body).to include("Team feature")
        expect(response.body).to include("Upgrade to Team")
        expect(response.body).to include("/pricing")
      end
    end

    context "when the user is a non-admin member of a Team org" do
      let(:member) do
        u = User.create!(
          email: "dev@example.com",
          password: "SecurePassword123!",
          confirmed_at: Time.current,
          plan_tier: :free
        )
        organization.memberships.create!(user: u, role: :developer)
        u
      end

      before do
        sign_out owner
        sign_in member
      end

      it "denies access" do
        get organization_audit_events_path(organization)
        # Pundit's NotAuthorized handler redirects with an alert; we just verify it's not 200.
        expect(response).not_to have_http_status(:ok)
      end
    end

    context "when the user is not a member of the org at all" do
      let(:outsider) do
        User.create!(
          email: "outsider@example.com",
          password: "SecurePassword123!",
          confirmed_at: Time.current,
          plan_tier: :free
        )
      end

      before do
        sign_out owner
        sign_in outsider
      end

      it "denies access" do
        get organization_audit_events_path(organization)
        expect(response).not_to have_http_status(:ok)
      end
    end

    # CSV formula-injection defense (OWASP). Excel/Numbers/LibreOffice will
    # execute cell values starting with =, +, -, @, \t, or \r as formulas.
    # The CSV export must prefix each such cell with a single quote so the
    # spreadsheet treats it as a literal string.
    describe "CSV export formula-injection protection" do
      require "csv"

      # Isolated: drop the records created by the outer `before` block so
      # we can assert exactly on the rows produced by these hostile inputs.
      before { AuditEvent.delete_all }

      def parse_csv_rows(body)
        CSV.parse(body, headers: true)
      end

      it "prefixes a leading-equals actor name with a single quote" do
        attacker = User.create!(
          email: "attacker@example.com",
          password: "SecurePassword123!",
          confirmed_at: Time.current,
          name: "=HYPERLINK(\"http://evil.example\",\"click\")"
        )
        organization.memberships.create!(user: attacker, role: :developer)
        AuditEvent.create!(
          organization: organization,
          actor: attacker,
          action: "member_invited",
          metadata: {},
          created_at: 5.minutes.ago
        )

        get organization_audit_events_path(organization, format: :csv)
        rows = parse_csv_rows(response.body)

        expect(rows.length).to eq(1)
        expect(rows.first["Actor"]).to start_with("'=")
        expect(rows.first["Actor"]).to eq("'=HYPERLINK(\"http://evil.example\",\"click\")")
      end

      it "prefixes a leading-plus, leading-minus, and leading-at actor name" do
        [ "+cmd|calc", "-2+3+cmd|calc", "@SUM(A1:A9)" ].each_with_index do |hostile_name, i|
          u = User.create!(
            email: "hostile#{i}@example.com",
            password: "SecurePassword123!",
            confirmed_at: Time.current,
            name: hostile_name
          )
          organization.memberships.create!(user: u, role: :developer)
          AuditEvent.create!(
            organization: organization,
            actor: u,
            action: "member_invited",
            metadata: {},
            created_at: (i + 1).minutes.ago
          )
        end

        get organization_audit_events_path(organization, format: :csv)
        rows = parse_csv_rows(response.body)
        actors = rows.map { |r| r["Actor"] }

        expect(actors).to include("'+cmd|calc")
        expect(actors).to include("'-2+3+cmd|calc")
        expect(actors).to include("'@SUM(A1:A9)")
      end

      it "prefixes a leading-tab and leading-carriage-return actor name" do
        tab_user = User.create!(
          email: "tab@example.com",
          password: "SecurePassword123!",
          confirmed_at: Time.current,
          name: "\t=evil()"
        )
        cr_user = User.create!(
          email: "cr@example.com",
          password: "SecurePassword123!",
          confirmed_at: Time.current,
          name: "\r=evil()"
        )
        [ tab_user, cr_user ].each do |u|
          organization.memberships.create!(user: u, role: :developer)
          AuditEvent.create!(
            organization: organization,
            actor: u,
            action: "member_invited",
            metadata: {},
            created_at: 1.minute.ago
          )
        end

        get organization_audit_events_path(organization, format: :csv)
        rows = parse_csv_rows(response.body)
        actors = rows.map { |r| r["Actor"] }

        expect(actors.any? { |a| a.start_with?("'\t") }).to be(true)
        expect(actors.any? { |a| a.start_with?("'\r") }).to be(true)
      end

      it "sanitizes metadata JSON when the serialized form starts with a risky char" do
        # Normal hash metadata serializes to "{...}" which starts with a safe
        # character, but any future refactor that lets a raw string pass
        # through, or a bug that swaps key ordering to put a key beginning
        # with "=" first, could expose the Metadata column. We pin the
        # sanitizer behavior by making a record whose metadata.to_json is
        # guaranteed to start with "=" via a targeted stub on the retrieved
        # instance.
        benign_user = User.create!(
          email: "benign@example.com",
          password: "SecurePassword123!",
          confirmed_at: Time.current,
          name: "Benign"
        )
        organization.memberships.create!(user: benign_user, role: :developer)
        AuditEvent.create!(
          organization: organization,
          actor: benign_user,
          action: "member_invited",
          metadata: { note: "normal" },
          created_at: 1.minute.ago
        )

        # Intercept the #metadata reader on all AuditEvent instances for this
        # example so every row's metadata.to_json starts with "=".
        hostile = Object.new
        def hostile.to_json(*); "=SUM(A1:A9)"; end
        allow_any_instance_of(AuditEvent).to receive(:metadata).and_return(hostile)

        get organization_audit_events_path(organization, format: :csv)
        rows = parse_csv_rows(response.body)

        expect(rows.length).to eq(1)
        expect(rows.first["Metadata"]).to eq("'=SUM(A1:A9)")
      end

      it "leaves benign values untouched" do
        benign_user = User.create!(
          email: "normal@example.com",
          password: "SecurePassword123!",
          confirmed_at: Time.current,
          name: "Normal Name"
        )
        organization.memberships.create!(user: benign_user, role: :developer)
        AuditEvent.create!(
          organization: organization,
          actor: benign_user,
          action: "member_invited",
          metadata: { email: "x@y.com" },
          created_at: 1.minute.ago
        )

        get organization_audit_events_path(organization, format: :csv)
        rows = parse_csv_rows(response.body)

        expect(rows.first["Actor"]).to eq("Normal Name")
        expect(rows.first["Action"]).to eq("member_invited")
        expect(rows.first["Metadata"]).not_to start_with("'")
      end
    end
  end
end
