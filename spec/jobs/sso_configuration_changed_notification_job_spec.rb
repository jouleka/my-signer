require "rails_helper"

RSpec.describe SsoConfigurationChangedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :team_plan, notify_sso_activity: true) }
  let(:organization) { create(:organization, owner: admin) }
  let(:actor) { create(:user, name: "Ivan Admin", notify_sso_activity: true) }

  before do
    organization.memberships.find_or_create_by!(user: admin) { |m| m.role = :admin }
    create(:membership, user: actor, organization: organization, role: :admin)
  end

  it "notifies other admins (not the actor) when SSO is enabled" do
    expect {
      described_class.perform_now(
        organization_id: organization.id,
        actor_id: actor.id,
        event: "created"
      )
    }.to change(Notification, :count).by(1)

    notification = Notification.last
    expect(notification.user).to eq(admin)
    expect(notification.notification_type).to eq("sso_configuration_changed:created")
    expect(notification.message).to include("Ivan Admin")
  end

  it "skips users with notify_sso_activity disabled" do
    admin.update!(notify_sso_activity: false)

    expect {
      described_class.perform_now(organization_id: organization.id, actor_id: actor.id, event: "updated")
    }.not_to change(Notification, :count)
  end
end
