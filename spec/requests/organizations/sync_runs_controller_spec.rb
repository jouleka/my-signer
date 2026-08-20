require "rails_helper"

RSpec.describe "DELETE /organizations/:org/sync_runs/:job_name", type: :request do
  let(:user) { create(:user, plan_tier: :free) }
  let(:organization) { create(:organization, owner: user) }

  before do
    sign_in user, scope: :user
    post switch_organization_path(organization)
  end

  it "destroys the OrgSyncRun row for the given job and redirects with notice" do
    OrgSyncRun.create!(
      organization: organization,
      job_name: "keywords_rank",
      status: "error",
      started_at: 1.hour.ago,
      finished_at: 30.minutes.ago,
      error_message: "Some failure"
    )

    expect {
      delete organization_sync_run_path(organization, job_name: "keywords_rank")
    }.to change { OrgSyncRun.where(organization: organization, job_name: "keywords_rank").count }.from(1).to(0)

    expect(response).to redirect_to(authenticated_root_path)
    follow_redirect!
    expect(flash[:notice].to_s).to include("Cleared")
  end

  it "is a no-op (and still flashes) when the row was already gone" do
    delete organization_sync_run_path(organization, job_name: "keywords_rank")
    expect(response).to redirect_to(authenticated_root_path)
    follow_redirect!
    expect(flash[:notice].to_s).to include("already been cleared")
  end

  it "rejects an unknown job_name with an alert" do
    OrgSyncRun.create!(
      organization: organization,
      job_name: "keywords_rank",
      status: "error",
      started_at: 1.hour.ago,
      finished_at: 30.minutes.ago,
      error_message: "Some failure"
    )

    delete organization_sync_run_path(organization, job_name: "not_a_real_job")
    expect(response).to redirect_to(authenticated_root_path)
    follow_redirect!
    expect(flash[:alert].to_s).to include("Unknown sync job")
    # The legitimate row must NOT have been touched
    expect(OrgSyncRun.where(organization: organization, job_name: "keywords_rank")).to exist
  end

  it "redirects unauthenticated callers to the sign-in page" do
    sign_out :user

    organization # eager-create so we have a valid path id without needing the session
    delete organization_sync_run_path(organization, job_name: "keywords_rank")

    expect(response).to have_http_status(:redirect)
    expect(response.location).to include(new_user_session_path)
  end

  it "redirects with an alert when the org doesn't belong to the current user" do
    other_user = create(:user, plan_tier: :free)
    other_org = create(:organization, owner: other_user)
    OrgSyncRun.create!(
      organization: other_org,
      job_name: "keywords_rank",
      status: "error",
      started_at: 1.hour.ago,
      finished_at: 30.minutes.ago,
      error_message: "Some failure"
    )

    delete organization_sync_run_path(other_org, job_name: "keywords_rank")
    expect(response).to redirect_to(authenticated_root_path)
    follow_redirect!
    expect(flash[:alert].to_s).to include("Organization not found")
    # Cross-org row must remain intact
    expect(OrgSyncRun.where(organization: other_org, job_name: "keywords_rank")).to exist
  end
end
