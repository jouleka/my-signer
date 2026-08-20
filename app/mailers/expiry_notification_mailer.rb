class ExpiryNotificationMailer < ApplicationMailer
  def expiry_warning(user:, resource:, days_remaining:)
    @user = user
    @resource = resource
    @days_remaining = days_remaining
    @resource_name = resource.respond_to?(:name) ? resource.name : "Resource"
    @resource_type = resource.class.name.titleize

    subject = if days_remaining == 0
      "Action Required: #{@resource_type} '#{@resource_name}' expires today"
    else
      "Action Required: #{@resource_type} '#{@resource_name}' expires in #{@days_remaining} days"
    end

    mail(to: @user.email, subject: subject)
  end

  def expired_notice(user:, resource:)
    @user = user
    @resource = resource
    @resource_name = resource.respond_to?(:name) ? resource.name : "Resource"
    @resource_type = resource.class.name.titleize

    mail(
      to: @user.email,
      subject: "Urgent: #{@resource_type} '#{@resource_name}' has expired"
    )
  end
end
