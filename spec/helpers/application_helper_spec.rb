# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#template_preview_bg color whitelisting" do
    it "passes through valid hex colors" do
      css = helper.template_preview_bg(
        "background_type" => "gradient",
        "gradient_start" => "#abc",
        "gradient_end" => "#112233ff"
      )
      expect(css).to eq("linear-gradient(to bottom, #abc, #112233ff)")
    end

    it "accepts conservative named colors" do
      css = helper.template_preview_bg(
        "background_type" => "solid",
        "background_color" => "transparent"
      )
      expect(css).to eq("transparent")
    end

    it "rejects CSS injection in a color value and falls back to the default" do
      css = helper.template_preview_bg(
        "background_type" => "gradient",
        "gradient_start" => "red; background: url(//evil)",
        "gradient_end" => "#764BA2"
      )
      expect(css).to eq("linear-gradient(to bottom, #000000, #764BA2)")
    end

    it "falls back to default for blank/unknown values" do
      expect(helper.safe_css_color(nil, "#000000")).to eq("#000000")
      expect(helper.safe_css_color("notacolor", "#000000")).to eq("#000000")
      expect(helper.safe_css_color("url(x)", "#000000")).to eq("#000000")
    end
  end
end
