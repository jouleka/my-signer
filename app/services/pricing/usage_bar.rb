module Pricing
  UsageBar = Struct.new(
    :label,
    :current,
    :max,
    :unit,
    :is_projection,
    :multiplier,
    keyword_init: true
  ) do
    def is_projection?
      is_projection
    end

    def percent
      return nil if is_projection
      return 0 if max.to_i.zero?
      ((current.to_f / max) * 100).clamp(0, 100).round
    end
  end
end
