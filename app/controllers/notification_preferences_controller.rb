class NotificationPreferencesController < ApplicationController
  before_action :authenticate_user!

  def show
    redirect_to settings_path(tab: "notifications")
  end

  def update
    @user = current_user
    if @user.update(notification_params)
      redirect_to settings_path(tab: "notifications"), notice: "Notification preferences updated successfully."
    else
      # If there are errors, we might want to render the settings page with the errors.
      # But for simplicity, let's redirect with an alert or rely on flash.
      # Better yet, let's render the settings/show view but we need to set up @api_tokens etc.
      # This is getting complicated for a simple embedded form.
      # Simplest valid approach: Redirect with alert.
      redirect_to settings_path(tab: "notifications"), alert: "Failed to update preferences: #{@user.errors.full_messages.join(', ')}"
    end
  end

  private

  def notification_params
    params.require(:user).permit(
      :email_notifications_enabled,
      :notify_certificate_expiry,
      :notify_profile_expiry,
      :notify_keystore_expiry,
      :notify_sync_failures,
      :notify_sync_changes,
      :notify_revocations,
      :notify_team_activity,
      :notify_member_activity,
      :notify_api_token_activity,
      :notify_sso_activity,
      :notify_security_alerts,
      :notify_billing_changes,
      :notify_release_activity,
      :notify_audit_digest,
      :notification_days_before
    )
  end
end
