module Aso
  module Countries
    # Derived from Storefronts::IDS — every country we have a storefront for
    # is a supported country for tracking.
    SUPPORTED = Aso::Storefronts::IDS.keys.freeze
  end
end
