require "rails_helper"

RSpec.describe "DELETE /billing/trial", type: :request do
  def make_user(email: "u-#{SecureRandom.hex(4)}@example.test")
    # `onboarding_completed_at` is required so ApplicationController's
    # onboarding-gate before_action doesn't redirect us to /onboarding
    # before the trials controller can run.
    User.create!(email: email, password: "Password123!",
                 accepts_terms: "1",
                 confirmed_at: Time.current,
                 onboarding_completed_at: Time.current)
  end

  it "downgrades a trialing user to free, clears trial fields, and audits per owned org" do
    user = User.with_reverse_trial { make_user(email: "trial-#{SecureRandom.hex(4)}@example.test") }
    org = Organization.create!(name: "Trial Co", owner: user)
    sign_in user

    user.reload
    expect(user.on_active_trial?).to be(true)
    expect {
      delete billing_trial_path
    }.to change { AuditEvent.where(action: "trial_ended_by_user").count }.by(1)

    user.reload
    expect(user.plan_tier).to eq("free")
    expect(user.trial_ends_at).to be_nil
    expect(user.trial_started_at).to be_nil
    expect(response).to redirect_to(pricing_path)
    expect(flash[:notice]).to include("Free plan")

    audit = AuditEvent.where(action: "trial_ended_by_user").last
    expect(audit.organization_id).to eq(org.id)
    expect(audit.actor_id).to eq(user.id)
  end

  it "redirects to pricing without flash error when user is not on a trial" do
    user = make_user # trial-skip is on by default in the spec env
    sign_in user

    expect(user.on_active_trial?).to be(false)
    delete billing_trial_path
    expect(response).to redirect_to(pricing_path)
    expect(flash[:alert]).to include("No active trial")
  end

  it "redirects unauthenticated callers to the sign-in page" do
    delete billing_trial_path
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include(new_user_session_path)
  end
end
