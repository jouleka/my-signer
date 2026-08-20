require "rails_helper"

RSpec.describe ApiTokenRevokedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin_user) { create(:user, :team_plan, notify_api_token_activity: true) }
  let(:organization) { create(:organization, owner: admin_user) }
  let(:revoker) { create(:user, name: "Alice Admin", notify_api_token_activity: true) }

  before do
    organization.memberships.find_or_create_by!(user: admin_user) { |m| m.role = :admin }
    create(:membership, user: revoker, organization: organization, role: :admin)
  end

  describe "#perform" do
    it "notifies admin members except the revoker" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          revoker_id: revoker.id,
          token_name: "CI Token"
        )
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification.user).to eq(admin_user)
      expect(notification.notification_type).to eq("api_token_revoked")
      expect(notification.message).to include("Alice Admin")
      expect(notification.message).to include("CI Token")
    end

    it "respects notify_api_token_activity preference" do
      admin_user.update!(notify_api_token_activity: false)

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          revoker_id: revoker.id,
          token_name: "CI Token"
        )
      }.not_to change(Notification, :count)
    end

    it "silently returns when organization not found" do
      expect {
        described_class.perform_now(organization_id: -1, revoker_id: revoker.id, token_name: "X")
      }.not_to change(Notification, :count)
    end
  end
end
