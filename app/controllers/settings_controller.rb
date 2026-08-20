class SettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
    @api_tokens = current_user.api_tokens.order(created_at: :desc)
    @memberships = current_user.memberships.includes(:organization).order(created_at: :desc)
    @billing_subscription = current_user.current_billing_subscription
  end
end
