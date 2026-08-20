require "rails_helper"

RSpec.describe AppleApp, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }

  describe "#primary_locale" do
    it "returns en-US when raw_json has no primaryLocale" do
      app = create(:apple_app, organization: organization)
      expect(app.primary_locale).to eq("en-US")
    end

    it "returns the primaryLocale from raw_json when set" do
      app = create(:apple_app, :en_gb_primary, organization: organization)
      expect(app.primary_locale).to eq("en-GB")
    end

    it "returns the de-DE primaryLocale from raw_json when set" do
      app = create(:apple_app, :de_de_primary, organization: organization)
      expect(app.primary_locale).to eq("de-DE")
    end

    it "returns en-US fallback when raw_json is nil" do
      app = create(:apple_app, organization: organization)
      app.update_columns(raw_json: nil)
      expect(app.primary_locale).to eq("en-US")
    end

    it "returns en-US fallback when raw_json has no attributes block" do
      app = create(:apple_app, organization: organization)
      app.update_columns(raw_json: { "id" => "x" })
      expect(app.primary_locale).to eq("en-US")
    end

    it "returns en-US when primaryLocale is blank" do
      app = create(:apple_app, organization: organization)
      app.update_columns(raw_json: { "attributes" => { "primaryLocale" => "" } })
      expect(app.primary_locale).to eq("en-US")
    end
  end
end
