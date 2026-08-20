class OrganizationInvitationMailer < ApplicationMailer
  def invite(invitation_id)
    @invite = OrganizationInvitation.find(invitation_id)
    @organization = @invite.organization
    @url = accept_organization_invitation_url(token: @invite.token)
    mail to: @invite.email, subject: "You're invited to join #{@organization.name}"
  end
end
