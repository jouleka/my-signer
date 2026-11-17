class ReleaseNotePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(organization_id: user.organizations.select(:id))
    end
  end

  def index?
    member_of_organization?
  end

  def show?
    member_of_organization?
  end

  def create?
    developer_or_higher?
  end

  def new?
    create?
  end

  def update?
    developer_or_higher? && record.content_editable? && !record.ai_pending?
  end

  def edit?
    update?
  end

  def destroy?
    admin_or_owner?
  end

  def apply?
    developer_or_higher? && record.content_editable? && !record.review_required? && !record.ai_pending?
  end

  def translate?
    developer_or_higher? && record.content_editable?
  end

  def rewrite?
    translate?
  end

  def diff?
    member_of_organization?
  end

  def history?
    member_of_organization?
  end

  def submit_for_review?
    developer_or_higher? && record.status == "draft" && !record.ai_pending? && record.organization.supports_review_workflow?
  end

  def approve_review?
    admin_or_owner? && record.status == "pending_review" && record.organization.supports_review_workflow?
  end

  def reject_review?
    admin_or_owner? && record.status == "pending_review" && record.organization.supports_review_workflow?
  end

  private

  def organization
    record.is_a?(Organization) ? record : record.organization
  end

  def member_of_organization?
    organization.accessible? && organization.memberships.exists?(user_id: user.id)
  end

  def developer_or_higher?
    return false unless member_of_organization?
    membership = organization.memberships.find_by(user_id: user.id)
    organization.owner_id == user.id || membership&.role.in?(%w[admin developer])
  end

  def admin_or_owner?
    return false unless member_of_organization?
    membership = organization.memberships.find_by(user_id: user.id)
    organization.owner_id == user.id || membership&.role == "admin"
  end
end
