class MembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_org

  def create
    # Authorize FIRST (create? = admin/owner) so the consent gate's
    # 404-vs-redirect difference below can't be used by a non-admin member as
    # an invited-or-not enumeration oracle — only admins/owners get past here.
    @membership = @org.memberships.new
    authorize @membership, :create?

    # Consent gate: an admin/owner may only materialize a membership for a user
    # who has an outstanding (active) or already-accepted invitation to THIS
    # org. This blocks adding an arbitrary registered user by id with no
    # consent (M-4). Arbitrary, uninvited, and non-existent user ids all resolve
    # to the same uniform 404, so the endpoint can't be used as an enumeration
    # oracle.
    @membership.assign_attributes(role: create_role, user: consenting_invited_user!)

    saved = false
    @org.with_lock do
      saved = @membership.save
    end

    if saved
      Audit::Logger.log(
        action: "member_added",
        resource: @membership,
        metadata: { user_id: @membership.user_id, role: @membership.role },
        organization: @org,
        request: request
      )
      redirect_to @org, notice: "Member added"
    else
      return if render_quota_exhausted_json_for(@membership)

      store_quota_upgrade_prompt!(@membership)
      redirect_to @org, alert: quota_exhausted_message(@membership)
    end
  end

  def update
    @membership = @org.memberships.find(params[:id])
    authorize @membership
    old_role = @membership.role
    if @membership.update(update_params)
      Audit::Logger.log(
        action: "member_role_changed",
        resource: @membership,
        metadata: { user_id: @membership.user_id, old_role: old_role, new_role: @membership.role },
        organization: @org,
        request: request
      )
      MembershipChangedNotificationJob.perform_later(
        organization_id: @org.id,
        actor_id: current_user.id,
        target_user_id: @membership.user_id,
        event: "role_changed",
        metadata: { old_role: old_role.to_s, new_role: @membership.role.to_s }
      )
      redirect_to @org, notice: "Member updated"
    else
      redirect_to @org, alert: @membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    @membership = @org.memberships.find(params[:id])
    authorize @membership
    target_user_id = @membership.user_id
    role = @membership.role

    if @membership.destroy
      Audit::Logger.log(
        action: "member_removed",
        metadata: { user_id: target_user_id, role: role },
        organization: @org,
        request: request
      )
      MembershipChangedNotificationJob.perform_later(
        organization_id: @org.id,
        actor_id: current_user.id,
        target_user_id: target_user_id,
        event: "removed",
        metadata: { role: role.to_s }
      )
      redirect_to @org, notice: "Member removed"
    else
      redirect_to @org, alert: @membership.errors.full_messages.to_sentence
    end
  end

  private

  def set_org
    # Scoped to caller's orgs so non-member access 404s like a missing id —
    # closes the org-id enumeration oracle. See
    # OrganizationsController#set_organization for full rationale.
    @org = current_user.organizations.find(params[:organization_id])
  end

  # Resolves the invited user the caller is consenting to add, or raises
  # ActiveRecord::RecordNotFound (uniform 404) when the supplied user_id does
  # not correspond to a user with an active or accepted invitation to this org.
  # Both "no such user" and "user exists but was never invited" intentionally
  # yield the same response so the endpoint isn't an enumeration oracle.
  def consenting_invited_user!
    user_id = params.require(:membership).permit(:user_id)[:user_id]
    raise ActiveRecord::RecordNotFound if user_id.blank?

    user = User.find_by(id: user_id)
    raise ActiveRecord::RecordNotFound if user.nil? || !invited?(user)

    user
  end

  # True when the target user has an outstanding (active) invitation, or one
  # they already accepted, matching their email for this org. Invitations key
  # on email, so we match case-insensitively on the user's email.
  def invited?(user)
    email = user.email.to_s
    return false if email.blank?

    scope = @org.organization_invitations.where("LOWER(email) = ?", email.downcase)
    scope.active.exists? || scope.where.not(accepted_at: nil).exists?
  end

  def create_role
    params.require(:membership).permit(:role)[:role]
  end

  # L-6: only the role may be assigned on update. The membership's user_id is
  # immutable here, so a membership can never be reassigned to another user.
  def update_params
    params.require(:membership).permit(:role)
  end
end
