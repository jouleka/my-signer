require "rails_helper"
require "cgi"

RSpec.describe "OrganizationsController", type: :request do
  let(:user) { create(:user, plan_tier: :free) }

  before do
    sign_in user, scope: :user
  end

  it "renders the organization-create gate state in the modal variant at the free cap" do
    create(:organization, owner: user, name: "Existing Org")

    get organizations_path

    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    form = doc.at_css("dialog#create-org-modal form")
    prompt = JSON.parse(form["data-upgrade-gate-prompt-value"])

    expect(form["data-upgrade-gate-blocked-value"]).to eq("true")
    expect(form["data-upgrade-gate-close-nearest-dialog-value"]).to eq("true")
    expect(prompt).to include(
      "current_plan" => "free",
      "required_plan" => "pro",
      "feature" => "organization",
      "source" => "organizations#index:create-organization"
    )
  end

  it "shows a no-results state instead of the first-organization create prompt when the search is empty" do
    create(:organization, owner: user, name: "Existing Org")

    get organizations_path, params: { q: "missing" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No organizations match this search")
    expect(response.body).not_to include("Create your first organization")
  end

  it "does not inject create-form validation errors on a plain index load" do
    create(:organization, owner: user, name: "Existing Org")

    get organizations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Name can't be blank")
    expect(response.body).not_to include("Name can't be blank and You can create a maximum of 1 organizations on the Free plan")
    expect(response.body).not_to include("modal.showModal")
  end

  it "does not pre-populate create-form validation errors on a plain GET" do
    create(:organization, owner: user, name: "Existing Org")

    get organizations_path

    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    modal = doc.at_css("dialog#create-org-modal")

    expect(modal.text).not_to include("Name can't be blank")
    expect(response.body).not_to include("modal.showModal")
  end

  it "shows upgrade guidance when the owned-organization limit is reached" do
    create(:organization, owner: user, name: "Existing Org")

    expect {
      post organizations_path, params: {
        organization: { name: "One Too Many" }
      }
    }.not_to change(Organization, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("maximum of 1 organizations")
    expect(response.body).to include("Upgrade from Free to Pro to increase the organization limit.")
    expected_prompt = Pricing::UpgradePromptPayload.for_quota_record(
      Organization.new(owner: user, name: "One Too Many").tap(&:valid?),
      source: "organizations#create"
    )

    expect(flash[:upgrade_prompt]).to eq(expected_prompt.deep_stringify_keys)
    expect(CGI.unescapeHTML(response.body)).to include('"required_plan":"pro"')
  end

  it "shows blocked organizations on the index and prevents opening them" do
    user.update!(plan_tier: :team)
    organizations = Array.new(5) { |index| create(:organization, owner: user, name: "Org #{index + 1}") }
    user.update!(plan_tier: :pro)
    Pricing::PlanEnforcer.new(user).apply!

    get organizations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Blocked by plan")
    expect(response.body).to include("Upgrade")

    get organization_path(organizations.last)

    expect(response).to redirect_to(authenticated_root_path)
    follow_redirect!
    expect(response.body).to include("You are not authorized to perform this action.")
  end

  it "automatically normalizes stale organization access for existing free users" do
    user.update_column(:plan_tier, User.plan_tiers.fetch("team"))
    organizations = Array.new(3) { |index| create(:organization, owner: user, name: "Org #{index + 1}", created_at: (3 - index).days.ago) }
    user.update_columns(plan_tier: User.plan_tiers.fetch("free"), last_organization_id: organizations.last.id)

    get organizations_path

    expect(response).to have_http_status(:ok)
    expect(organizations.first.reload.access_state).to eq("active")
    expect(organizations.drop(1).map { |org| org.reload.access_state }).to all(eq("plan_blocked"))
    expect(user.reload.last_organization_id).to eq(organizations.first.id)
    expect(response.body).to include("Blocked by plan")
    expect(response.body).not_to include(switch_organization_path(organizations.last))
  end

  it "prevents switching into blocked organizations" do
    user.update!(plan_tier: :team)
    organizations = Array.new(5) { |index| create(:organization, owner: user, name: "Org #{index + 1}") }
    user.update!(plan_tier: :pro)
    Pricing::PlanEnforcer.new(user).apply!

    post switch_organization_path(organizations.last)

    expect(response).to redirect_to(authenticated_root_path)
    follow_redirect!
    expect(response.body).to include("You are not authorized to perform this action.")
  end

  it "renders persistent downgrade warnings for seats and screenshot projects" do
    organization = create(:organization, owner: user, name: "Overflow Org")
    teammate = create(:user, email: "teammate@example.com")

    user.update!(plan_tier: :team)
    organization.memberships.create!(user: teammate, role: :developer)
    organization.organization_invitations.create!(inviter: user, email: "pending@example.com", role: :viewer)
    create(:screenshot_project, organization: organization, name: "Project 1", created_at: 2.days.ago)
    create(:screenshot_project, organization: organization, name: "Project 2", created_at: 1.day.ago)

    user.update!(plan_tier: :free)

    get organization_path(organization)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Usage exceeds plan limits")
    expect(response.body).to include("Seats")
    expect(response.body).to include("Screenshot projects")
    expect(response.body).to include("Project 2")
  end

  describe "DELETE /organizations/:id" do
    # Regression guard for the audit-trail hole where the `organization_deleted`
    # event was lost. The logger previously ran AFTER destroy, which meant the
    # org was already gone and the FK rejected the insert. The controller now
    # writes the event inside a transaction BEFORE destroy, and the DB FK
    # nullifies organization_id as part of the destroy. The event row must
    # still exist afterward with the deleted org's id captured in metadata.
    it "records an organization_deleted audit event that survives the destroy" do
      organization = create(:organization, owner: user, name: "To Be Deleted")
      deleted_org_id = organization.id

      expect {
        delete organization_path(organization)
      }.to change(AuditEvent.where(action: "organization_deleted"), :count).by(1)

      expect(Organization.exists?(deleted_org_id)).to be false

      event = AuditEvent.where(action: "organization_deleted").last
      expect(event).to be_present
      expect(event.organization_id).to be_nil
      expect(event.metadata["name"]).to eq("To Be Deleted")
      expect(event.metadata["organization_id"]).to eq(deleted_org_id)
    end
  end
end
