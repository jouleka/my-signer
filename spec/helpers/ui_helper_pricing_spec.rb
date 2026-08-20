require "rails_helper"

RSpec.describe UiHelper, type: :helper do
  describe "#pricing_tier_accent_classes" do
    it "returns neutral tokens for free" do
      result = helper.pricing_tier_accent_classes("free")
      expect(result).to include(:border, :accent_text)
      expect(result[:border]).to include("base-content")
    end

    it "returns primary-purple tokens for pro" do
      result = helper.pricing_tier_accent_classes("pro")
      expect(result[:border]).to include("primary")
      expect(result[:accent_text]).to include("primary")
    end

    it "returns warning-amber tokens for team" do
      result = helper.pricing_tier_accent_classes("team")
      expect(result[:border]).to include("warning")
      expect(result[:accent_text]).to include("warning")
    end
  end

  describe "#pricing_card_classes" do
    it "returns base card classes for any tier" do
      result = helper.pricing_card_classes(tier: "free", is_current: false, is_recommended: false)
      expect(result).to include("rounded-[0.875rem]")
      expect(result).to include("p-8")
    end

    it "adds the primary ring when is_recommended is true for pro" do
      result = helper.pricing_card_classes(tier: "pro", is_current: false, is_recommended: true)
      expect(result).to include("ring-2")
      expect(result).to include("ring-primary")
    end

    it "adds the warning ring when is_recommended is true for team" do
      result = helper.pricing_card_classes(tier: "team", is_current: false, is_recommended: true)
      expect(result).to include("ring-2")
      expect(result).to include("ring-warning")
    end

    it "adds a current-plan indicator when is_current is true" do
      result = helper.pricing_card_classes(tier: "team", is_current: true, is_recommended: false)
      expect(result).to include("is-current-plan")
    end
  end

  describe "#pricing_context_badge" do
    def ctx(viewer_type, trial_days: nil, scheduled_change: nil)
      Pricing::ViewerContext.new(viewer_type: viewer_type, trial_days: trial_days, scheduled_change: scheduled_change)
    end

    # Full matrix: 6 viewer types × 3 tiers = 18 cells
    [
      [ :prospect,     "free", nil ],
      [ :prospect,     "pro",  "Most popular" ],
      [ :prospect,     "team", nil ],
      [ :free,         "free", "Your plan" ],
      [ :free,         "pro",  "Most popular" ],
      [ :free,         "team", nil ],
      [ :pro_trialing, "free", nil ],
      [ :pro_trialing, "pro",  "Your trial" ],
      [ :pro_trialing, "team", nil ],
      [ :pro,          "free", nil ],
      [ :pro,          "pro",  "Your plan" ],
      [ :pro,          "team", "Most popular" ],
      [ :team,         "free", nil ],
      [ :team,         "pro",  nil ],
      [ :team,         "team", "Your plan" ]
    ].each do |viewer_type, tier, expected_substring|
      it "#{viewer_type} on #{tier} card renders #{expected_substring.inspect}" do
        viewer = viewer_type == :pro_trialing ? ctx(viewer_type, trial_days: 9) : ctx(viewer_type)
        html = helper.pricing_context_badge(tier: tier, viewer_context: viewer)
        if expected_substring.nil?
          expect(html).to be_nil.or be_blank
        else
          expect(html).to include(expected_substring)
        end
      end
    end

    it "renders 'Pending → Pro' on pro card when scheduled_change is team→pro" do
      viewer = ctx(:team, scheduled_change: { from: "team", to: "pro", effective_at: Date.current })
      html = helper.pricing_context_badge(tier: "pro", viewer_context: viewer)
      expect(html).to include("Pending")
      expect(html).to include("Pro")
    end
  end

  describe "#pricing_cta" do
    def ctx(viewer_type) = Pricing::ViewerContext.new(viewer_type: viewer_type)

    [
      [ :prospect,     "free", "Start for free",  false ],
      [ :prospect,     "pro",  "Start 14-day",    false ],
      [ :prospect,     "team", "Go Team",         false ],
      [ :free,         "free", "Your plan",       true ],
      [ :free,         "pro",  "Start Pro",       false ],
      [ :free,         "team", "Start Team",      false ],
      [ :pro_trialing, "free", "End trial",       false ],
      [ :pro_trialing, "pro",  "Activate Pro",    false ],
      [ :pro_trialing, "team", "Upgrade to Team", false ],
      [ :pro,          "free", "Downgrade",       false ],
      [ :pro,          "pro",  "Your plan",       true ],
      [ :pro,          "team", "Upgrade to Team", false ],
      [ :team,         "free", "Downgrade",       false ],
      [ :team,         "pro",  "Downgrade",       false ],
      [ :team,         "team", "Your plan",       true ]
    ].each do |viewer_type, tier, label, disabled|
      it "#{viewer_type} on #{tier}: label=#{label.inspect}, disabled=#{disabled}" do
        cta = helper.pricing_cta(tier: tier, viewer_context: ctx(viewer_type))
        expect(cta[:label]).to include(label)
        expect(cta[:disabled]).to be(disabled)
      end
    end
  end
end
