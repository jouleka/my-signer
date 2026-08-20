class NotificationMailer < ApplicationMailer
  def sync_failed(user:, credential_type:, organization:, error_message:)
    @user = user
    @credential_type = credential_type
    @organization = organization
    @error_message = error_message

    mail(
      to: @user.email,
      subject: "Sync Failed: #{@credential_type} for #{@organization.name}"
    )
  end

  def resource_revoked(user:, resource:, resource_type_label:)
    @user = user
    @resource = resource
    @resource_type_label = resource_type_label
    @resource_name = resource.respond_to?(:name) ? resource.name : "Resource"

    mail(
      to: @user.email,
      subject: "Urgent: #{@resource_type_label} '#{@resource_name}' has been revoked"
    )
  end

  def team_member_joined(user:, new_member:, organization:)
    @user = user
    @new_member = new_member
    @organization = organization

    mail(
      to: @user.email,
      subject: "#{@new_member.name || @new_member.email} joined #{@organization.name}"
    )
  end

  def api_token_created(user:, creator:, token_name:, organization:)
    @user = user
    @creator = creator
    @token_name = token_name
    @organization = organization

    mail(
      to: @user.email,
      subject: "New API Token created in #{@organization.name}"
    )
  end

  def api_token_revoked(user:, revoker:, token_name:, organization:)
    @user = user
    @revoker_name = revoker.name.presence || revoker.email
    @token_name = token_name
    @organization = organization

    mail(
      to: @user.email,
      subject: "API token revoked in #{@organization.name}"
    )
  end

  def sso_configuration_changed(user:, actor:, organization:, event:)
    @user = user
    @actor_name = actor.name.presence || actor.email
    @organization = organization
    @event = event
    mail(
      to: @user.email,
      subject: "SSO #{event} for #{@organization.name}"
    )
  end

  def sso_jit_user_provisioned(user:, provisioned_user:, organization:)
    @user = user
    @provisioned_user = provisioned_user
    @organization = organization
    mail(
      to: @user.email,
      subject: "New SSO user auto-provisioned in #{@organization.name}"
    )
  end

  def sync_completed(user:, organization:, changes_summary:)
    @user = user
    @organization = organization
    @changes_summary = changes_summary

    mail(
      to: @user.email,
      subject: "Sync completed with changes for #{@organization.name}"
    )
  end

  def member_role_changed(user:, actor:, target_user:, organization:, old_role:, new_role:)
    @user = user
    @actor_name = actor.name.presence || actor.email
    @target_name = target_user.name.presence || target_user.email
    @organization = organization
    @old_role = old_role
    @new_role = new_role
    mail(
      to: @user.email,
      subject: "Role changed in #{@organization.name}"
    )
  end

  def member_removed(user:, actor:, target_user:, organization:)
    @user = user
    @actor_name = actor.name.presence || actor.email
    @target_name = target_user.name.presence || target_user.email
    @organization = organization
    mail(
      to: @user.email,
      subject: "Member removed from #{@organization.name}"
    )
  end
end
