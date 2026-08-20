require "rails_helper"

RSpec.describe "Notification preferences update", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it "persists all granular preference toggles" do
    patch notification_preferences_path, params: {
      user: {
        email_notifications_enabled: "1",
        notify_member_activity: "0",
        notify_api_token_activity: "1",
        notify_sso_activity: "1",
        notify_security_alerts: "0",
        notify_billing_changes: "1",
        notify_release_activity: "0",
        notify_audit_digest: "1"
      }
    }

    user.reload
    expect(user.notify_member_activity?).to be false
    expect(user.notify_api_token_activity?).to be true
    expect(user.notify_sso_activity?).to be true
    expect(user.notify_security_alerts?).to be false
    expect(user.notify_billing_changes?).to be true
    expect(user.notify_release_activity?).to be false
    expect(user.notify_audit_digest?).to be true
  end
end
