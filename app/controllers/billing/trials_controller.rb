module Billing
  class TrialsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_trial_active!

    # User-initiated end-of-trial: drops the user from `pro` (trial) to
    # `free` immediately, clearing the trial timestamps so
    # TrialExpirationJob doesn't double-fire and so the "Trial · Nd left"
    # CTA stops showing.
    #
    # Only valid for users who are currently on a real reverse trial
    # (User#on_active_trial?). Users with an active Paddle subscription
    # cannot use this path -- they need the cancellation flow at
    # billing-cancel-modal which goes through Paddle to cancel billing.
    def destroy
      # Same row-locked transaction TrialExpirationJob#expire_trial! uses
      # so the row state and audit writes commit together. We re-check
      # eligibility under the lock to avoid racing a Paddle webhook that
      # might have just upgraded this user via checkout in another tab.
      committed = false
      User.transaction do
        current_user.lock!
        eligible = current_user.trial_ends_at.present? &&
                   current_user.pro? &&
                   !current_user.billing_subscriptions.active_for_entitlements.exists?

        if eligible
          current_user.update!(
            plan_tier: :free,
            trial_started_at: nil,
            trial_ends_at: nil
          )

          current_user.owned_organizations.find_each do |org|
            Audit::Logger.log(
              action: "trial_ended_by_user",
              actor: current_user,
              organization: org,
              metadata: { ended_at: Time.current },
              request: request
            )
          end

          committed = true
        end
      end

      if committed
        redirect_to pricing_path, notice: "Your trial has ended. You're now on the Free plan."
      else
        # Eligibility flipped between guard and lock (concurrent paddle
        # checkout) — bounce back without an error so the user lands on
        # whatever pricing-page state actually applies now.
        redirect_to pricing_path
      end
    end

    private

    # Runs as before_action -- Rails will halt the action chain when this
    # method calls redirect_to. The plain-method `redirect_to ... and return`
    # idiom doesn't halt a controller action when called from inside it,
    # so we register this as a before_action and let Rails do the halting.
    def authorize_trial_active!
      return if current_user.on_active_trial?

      redirect_to pricing_path, alert: "No active trial to end."
    end
  end
end
