module Billing
  class SubscriptionChangePreviewPresenter
    def initialize(preview:, current_subscription:, target_tier:, target_interval:, policy:)
      @preview = preview || {}
      @current_subscription = current_subscription
      @target_tier = target_tier.to_s
      @target_interval = target_interval.to_s
      @policy = policy
      # For items_unchanged transitions (Keep-plan undo), the "target" is
      # really the current plan — there's no change to bill — so pull the
      # recurring price from the current catalog entry instead of the
      # transition target.
      offering_tier = @policy.respond_to?(:items_unchanged?) && @policy.items_unchanged? ? @current_subscription&.plan_tier.to_s : @target_tier
      offering_interval = @policy.respond_to?(:items_unchanged?) && @policy.items_unchanged? ? @current_subscription&.billing_interval.to_s : @target_interval
      @target_offering = Billing::PlanCatalog.fetch(tier: offering_tier, interval: offering_interval)
    end

    def to_h
      {
        title: title,
        timing_label: timing_label,
        message: @policy.message,
        due_today: money_summary_for(
          amount_cents: extract_amount_cents(immediate_transaction),
          currency_code: extract_currency_code(immediate_transaction)
        ),
        next_charge: money_summary_for(
          amount_cents: extract_amount_cents(next_transaction) || target_offering[:price_cents],
          currency_code: extract_currency_code(next_transaction),
          date: next_charge_date
        ),
        recurring_charge: money_summary_for(
          amount_cents: extract_amount_cents(recurring_transaction_details) || target_offering[:price_cents],
          currency_code: extract_currency_code(recurring_transaction_details)
        ),
        summary_line: summary_line,
        effective_at: effective_at&.iso8601
      }
    end

    private

    def title
      "#{@target_tier.titleize} #{@target_interval.titleize}"
    end

    def timing_label
      if @policy.immediate_change?
        "Applies now"
      else
        "Starts at renewal"
      end
    end

    def summary_line
      summary = update_summary
      action = summary.dig("result", "action").presence
      amount_cents = extract_amount_cents(summary)

      return "No extra prorated credit or charge is expected for this change." if action.blank? || amount_cents.blank? || amount_cents.zero?

      formatted = format_currency(amount_cents, extract_currency_code(summary))
      case action
      when "credit"
        "A prorated credit of #{formatted} is expected as part of this change."
      when "charge", "bill"
        "A prorated charge of #{formatted} is expected as part of this change."
      else
        "This change includes a prorated adjustment of #{formatted}."
      end
    end

    def money_summary_for(amount_cents:, currency_code:, date: nil)
      {
        amount_cents: amount_cents,
        currency_code: currency_code,
        formatted_amount: amount_cents.present? ? format_currency(amount_cents, currency_code) : nil,
        date: date&.iso8601,
        formatted_date: date.present? ? I18n.l(date, format: :long) : nil
      }
    end

    def next_charge_date
      parse_time(@preview["next_billed_at"]) ||
        parse_time(next_transaction.dig("billing_period", "starts_at")) ||
        effective_at ||
        @current_subscription&.current_period_ends_at
    end

    def effective_at
      parse_time(@preview.dig("scheduled_change", "effective_at")) || @current_subscription&.current_period_ends_at
    end

    def immediate_transaction
      @preview["immediate_transaction"] || {}
    end

    def next_transaction
      @preview["next_transaction"] || {}
    end

    def recurring_transaction_details
      @preview["recurring_transaction_details"] || {}
    end

    def update_summary
      @preview["update_summary"] || {}
    end

    def extract_amount_cents(payload)
      value = first_present_value(
        payload,
        %w[details totals total],
        %w[details totals grand_total],
        %w[totals total],
        %w[totals grand_total],
        %w[result amount],
        %w[amount]
      )
      return nil if value.blank?

      value.to_i
    end

    def extract_currency_code(payload)
      first_present_value(
        payload,
        %w[details totals currency_code],
        %w[totals currency_code],
        %w[result currency_code],
        %w[currency_code]
      ) || target_offering[:currency]
    end

    def first_present_value(payload, *paths)
      paths.each do |path|
        value = path.reduce(payload) { |memo, key| memo.respond_to?(:[]) ? memo[key] : nil }
        return value if value.present?
      end

      nil
    end

    def format_currency(amount_cents, currency_code)
      amount = BigDecimal(amount_cents.to_s) / 100
      precision = (amount.frac.zero? ? 0 : 2)
      ApplicationController.helpers.number_to_currency(amount, unit: currency_unit(currency_code), precision: precision)
    end

    def currency_unit(currency_code)
      currency_code.to_s.upcase == "USD" ? "$" : "#{currency_code} "
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    attr_reader :target_offering
  end
end
