module Organizations
  class SyncRunsController < ApplicationController
    # ApplicationController deliberately doesn't install a global
    # `authenticate_user!` (its plan/onboarding/current-attribute
    # filters early-return on `!user_signed_in?`), so authed
    # controllers must declare it themselves. Without this line, the
    # action below derefs `current_user.organizations.find(...)` →
    # NoMethodError on nil → 500. That's not auth, it's a crash being
    # reused as auth, and the next refactor that touches
    # `set_organization` could turn it into a real bypass.
    before_action :authenticate_user!
    before_action :set_organization

    # Dismisses a single failed sync-job by destroying its OrgSyncRun
    # row. Use case: a job has stranded (worker died) and the user has
    # exhausted the obvious fixes -- they just want the red card to go
    # away so the dashboard isn't shouting at them. The next sync run
    # rebuilds the row from scratch via OrgSyncRun.record_started!, so
    # this is non-destructive to forward sync behavior.
    #
    # Authorized via OrganizationPolicy#sync? -- if you can trigger
    # syncs, you can also clear failed sync rows.
    def destroy
      authorize @organization, :sync?

      job_name = params[:job_name].to_s
      unless OrgSyncRun::JOB_NAMES.include?(job_name)
        redirect_to authenticated_root_path, alert: "Unknown sync job."
        return
      end

      run = OrgSyncRun.find_by(organization_id: @organization.id, job_name: job_name)
      run&.destroy

      redirect_to authenticated_root_path,
                  notice: run ? "Cleared the #{job_name.tr('_', ' ')} sync error. Triggering a fresh sync will retry it from scratch." :
                                "That sync error has already been cleared."
    end

    private

    def set_organization
      @organization = current_user.organizations.find(params[:organization_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to authenticated_root_path, alert: "Organization not found."
    end
  end
end
