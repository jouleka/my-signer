class PricingController < ApplicationController
  def show
    @organization = user_signed_in? ? current_organization : nil
    @plan_payload = Pricing::PlanPayload.for_organization(@organization) if @organization.present?
    @billing_offerings = Billing::PlanCatalog.offerings
    @billing_subscription = current_user&.current_billing_subscription
    @viewer_context = Pricing::ViewerContext.build(
      user: current_user,
      organization: @organization,
      subscription: @billing_subscription,
      plan_payload: @plan_payload
    )
  end
end
