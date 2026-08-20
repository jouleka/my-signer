require "rails_helper"

RSpec.describe SsoJitProvisionedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :team_plan, notify_sso_activity: true) }
  let(:organization) { create(:organization, owner: admin) }
  let(:provisioned) { create(:user, email: "new@company.com", name: "New User") }

  before do
    organization.memberships.find_or_create_by!(user: admin) { |m| m.role = :admin }
  end

  it "notifies admins that a new user was auto-provisioned via SSO" do
    expect {
      described_class.perform_now(
        organization_id: organization.id,
        provisioned_user_id: provisioned.id
      )
    }.to change(Notification, :count).by(1)

    notification = Notification.last
    expect(notification.user).to eq(admin)
    expect(notification.notification_type).to eq("sso_jit_provisioned")
    expect(notification.message).to include("new@company.com")
  end

  it "skips notification when admin has notify_sso_activity disabled" do
    admin.update!(notify_sso_activity: false)

    expect {
      described_class.perform_now(organization_id: organization.id, provisioned_user_id: provisioned.id)
    }.not_to change(Notification, :count)
  end
end
