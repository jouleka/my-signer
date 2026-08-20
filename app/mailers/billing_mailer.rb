class BillingMailer < ApplicationMailer
  def plan_changed(user:, from_tier:, to_tier:)
    @user = user
    @from_tier = from_tier.to_s.capitalize
    @to_tier = to_tier.to_s.capitalize
    @upgraded = Pricing::Entitlements::PLAN_SEQUENCE.index(to_tier.to_s).to_i >
                Pricing::Entitlements::PLAN_SEQUENCE.index(from_tier.to_s).to_i

    subject = @upgraded ? "Welcome to MySigner #{@to_tier}" : "Your MySigner plan changed to #{@to_tier}"
    mail(to: @user.email, subject: subject)
  end

  def payment_past_due(user:)
    @user = user
    mail(
      to: @user.email,
      subject: "Action needed — your MySigner payment is past due"
    )
  end

  def subscription_cancelled(user:)
    @user = user
    mail(
      to: @user.email,
      subject: "Your MySigner subscription was cancelled"
    )
  end

  # Sent immediately after a user requests account deletion. The
  # `restore_token` is the plain (un-hashed) one-time token returned by
  # User#soft_delete!; the deletion is reversible by clicking the link in
  # this email any time before `deletes_at`.
  def account_pending_deletion(user:, restore_token:, deletes_at:)
    @user          = user
    @restore_token = restore_token
    @deletes_at    = deletes_at
    mail(
      to: @user.email,
      subject: "Your MySigner account is scheduled for deletion on #{@deletes_at.strftime('%B %-d, %Y')}"
    )
  end

  # Sent on day-0 of the owner's grace window to every member who is NOT
  # the owner of an organization the deleting user owns. Privacy §8
  # discloses that "organizations you own" are deleted with the account;
  # this email is the courtesy notice that gives co-members the full
  # 90-day window to export their data before the cascade fires.
  def org_owner_pending_deletion(co_member:, owner:, organization:, deletes_at:)
    @co_member    = co_member
    @owner        = owner
    @organization = organization
    @deletes_at   = deletes_at
    mail(
      to: @co_member.email,
      subject: "#{@organization.name} on MySigner is scheduled for deletion on #{@deletes_at.strftime('%B %-d, %Y')}"
    )
  end
end
