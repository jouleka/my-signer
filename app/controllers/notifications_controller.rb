class NotificationsController < ApplicationController
  before_action :authenticate_user!
  after_action :verify_authorized

  def index
    skip_authorization # Notifications are user-scoped via current_user
    @notifications = current_user.notifications.visible.recent.page(params[:page]).per(20)
  end

  def dropdown
    skip_authorization # Notifications are user-scoped via current_user
    @notifications = current_user.notifications.visible.recent.limit(5)
    render layout: false
  end

  def click
    skip_authorization # Notifications are user-scoped via current_user
    notification = current_user.notifications.find(params[:id])
    notification.mark_as_read! unless notification.read?

    redirect_to target_url_for(notification)
  end

  def mark_as_read
    skip_authorization # Notifications are user-scoped via current_user
    notification = current_user.notifications.find(params[:id])
    notification.mark_as_read!

    respond_to do |format|
      format.html { redirect_back(fallback_location: notifications_path) }
      format.turbo_stream { render turbo_stream: turbo_stream.replace(notification, partial: "notifications/notification", locals: { notification: notification }) }
    end
  end

  def mark_all_as_read
    skip_authorization # Notifications are user-scoped via current_user
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_back(fallback_location: notifications_path, notice: "All notifications marked as read.")
  end

  def dismiss
    skip_authorization # Notifications are user-scoped via current_user
    notification = current_user.notifications.find(params[:id])
    notification.dismiss!

    respond_to do |format|
      format.html { redirect_back(fallback_location: notifications_path) }
      format.turbo_stream { render turbo_stream: turbo_stream.remove(notification) }
    end
  end

  private

  def target_url_for(notification)
    # For notification types that target the organization rather than a specific resource
    if notification.notification_type.in?(%w[sync_failed sync_completed team_member_joined])
      return notification.organization ? organization_path(notification.organization) : notifications_path
    end

    if notification.notification_type == "api_token_created" && notification.organization
      return organization_api_tokens_path(notification.organization)
    end

    return notifications_path unless notification.resource

    case notification.resource
    when AppleCertificate
      organization_apple_certificates_path(notification.organization, q: notification.resource.serial_number)
    when AppleProvisioningProfile
      organization_apple_provisioning_profiles_path(notification.organization, q: notification.resource.uuid)
    when AppReview
      organization_reviews_path(notification.organization)
    else
      begin
        polymorphic_url([ notification.organization, notification.resource ])
      rescue NoMethodError, ActionController::UrlGenerationError
        notifications_path
      end
    end
  end
end
