module Pricing
  class UpgradePromptPayload
    FEATURE_NAMES = {
      owned_organizations: "organization",
      seats: "seat",
      screenshot_projects: "screenshot project"
    }.freeze

    def self.build(current_plan:, feature:, message:, suggestion:, required_plan: nil, source: nil)
      {
        current_plan: current_plan.to_s,
        required_plan: required_plan.presence&.to_s,
        feature: feature.to_s,
        message: message,
        suggestion: suggestion,
        source: source
      }.compact
    end

    def self.for_quota_record(record, source: nil)
      detail = quota_detail(record)
      return unless detail

      build(
        current_plan: detail[:current_plan],
        required_plan: detail[:next_plan],
        feature: feature_name(detail[:feature]),
        message: quota_message(record),
        suggestion: quota_guidance(detail),
        source: source
      )
    end

    def self.plan_suggestion(current_plan:, required_plan:, feature:)
      current_name = current_plan.to_s.titleize
      required_name = required_plan.to_s.titleize

      if required_plan.present? && current_plan.to_s != required_plan.to_s
        "Upgrade from #{current_name} to #{required_name} to use #{feature}."
      else
        "Your #{current_name} plan doesn't include #{feature}."
      end
    end

    def self.quota_suggestion(current_plan:, next_plan:, feature:)
      current_name = current_plan.to_s.titleize

      if next_plan.present? && next_plan.to_s != current_plan.to_s
        "Upgrade from #{current_name} to #{next_plan.to_s.titleize} to increase the #{feature} limit."
      else
        "Your #{current_name} plan has reached its #{feature} limit."
      end
    end

    def self.quota_guidance(detail)
      current_plan = detail[:current_plan].to_s
      next_plan = detail[:next_plan].presence&.to_s
      feature = feature_name(detail[:feature])
      suggestion = quota_suggestion(current_plan: current_plan, next_plan: next_plan, feature: feature)

      if next_plan.present? && next_plan != current_plan
        suggestion
      else
        "#{suggestion} Reduce usage to continue."
      end
    end

    def self.feature_name(feature)
      FEATURE_NAMES.fetch(feature.to_sym, feature.to_s.tr("_", " "))
    end

    def self.quota_detail(record)
      Array(record.errors.details[:base]).find { |detail| detail[:error] == :quota_exhausted }
    end

    def self.quota_message(record)
      quota_error = record.errors.where(:base).find { |error| error.type == :quota_exhausted }
      quota_error&.full_message || record.errors.full_messages.to_sentence
    end
  end
end
