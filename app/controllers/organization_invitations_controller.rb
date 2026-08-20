class OrganizationInvitationsController < ApplicationController
  before_action :authenticate_user!, except: [ :accept ]

  def create
    org = current_user.organizations.find(params[:organization_id])
    invite = org.organization_invitations.new(invite_params.merge(inviter: current_user))
    authorize invite

    # Check if user can invite with requested role
    unless Pundit.policy!(current_user, invite).can_invite_role?(invite.role)
      redirect_back fallback_location: authenticated_root_path, alert: "You don't have permission to invite #{invite.role} members"
      return
    end

    saved = false
    org.with_lock do
      saved = invite.save
    end

    if saved
      Audit::Logger.log(
        action: "member_invited",
        resource: invite,
        metadata: { email: invite.email, role: invite.role },
        organization: org,
        request: request
      )
      mail = OrganizationInvitationMailer.invite(invite.id)
      Rails.env.development? ? mail.deliver_now : mail.deliver_later
      redirect_back fallback_location: authenticated_root_path, notice: "Invitation sent to #{invite.email}"
    else
      return if render_quota_exhausted_json_for(invite)

      store_quota_upgrade_prompt!(invite)
      redirect_back fallback_location: authenticated_root_path, alert: quota_exhausted_message(invite)
    end
  end

  def destroy
    invite = OrganizationInvitation.find(params[:id])
    authorize invite
    invite.cancel!
    Audit::Logger.log(
      action: "invitation_cancelled",
      resource: invite,
      metadata: { email: invite.email },
      organization: invite.organization,
      request: request
    )
    redirect_back fallback_location: authenticated_root_path, notice: "Invitation cancelled"
  rescue => e
    redirect_back fallback_location: authenticated_root_path, alert: e.message
  end

  def accept
    invite = OrganizationInvitation.active.find_by!(token: params[:token])
    authorize invite
    if current_user
      invite.accept!(current_user)
      Audit::Logger.log(
        action: "invitation_accepted",
        resource: invite,
        metadata: { email: invite.email, role: invite.role },
        actor: current_user,
        organization: invite.organization,
        request: request
      )
      TeamMemberJoinedNotificationJob.perform_later(
        organization_id: invite.organization_id,
        new_member_id: current_user.id
      )
      redirect_to authenticated_root_path, notice: "You've joined #{invite.organization.name}"
    else
      session[:pending_invite_token] = invite.token
      redirect_to new_user_session_path, notice: "Sign in to accept your invitation"
    end
  rescue => e
    redirect_to(current_user ? authenticated_root_path : unauthenticated_root_path, alert: e.message)
  end

  private

  def invite_params
    params.require(:organization_invitation).permit(:email, :role)
  end
end
