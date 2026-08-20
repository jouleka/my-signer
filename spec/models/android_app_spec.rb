require "rails_helper"

RSpec.describe AndroidApp, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }

  describe "#primary_locale" do
    it "returns the default_language when set" do
      app = create(:android_app, organization: organization, default_language: "de-DE")
      expect(app.primary_locale).to eq("de-DE")
    end

    it "returns the default_language when the :de_de_primary trait is used" do
      app = create(:android_app, :de_de_primary, organization: organization)
      expect(app.primary_locale).to eq("de-DE")
    end

    it "normalizes underscore format to hyphen" do
      app = create(:android_app, organization: organization, default_language: "pt_BR")
      expect(app.primary_locale).to eq("pt-BR")
    end

    it "normalizes the :pt_br_primary_underscore trait to hyphen format" do
      app = create(:android_app, :pt_br_primary_underscore, organization: organization)
      expect(app.primary_locale).to eq("pt-BR")
    end

    it "returns en-US when default_language is nil" do
      app = create(:android_app, organization: organization, default_language: nil)
      expect(app.primary_locale).to eq("en-US")
    end

    it "returns en-US when default_language is blank" do
      app = create(:android_app, organization: organization, default_language: "")
      expect(app.primary_locale).to eq("en-US")
    end

    it "strips whitespace from default_language before normalizing" do
      app = build(:android_app, organization: organization, default_language: "  ja  ")
      # before_validation :squish_fields strips whitespace during save, so we
      # assert the post-squish behaviour directly.
      app.save!
      expect(app.primary_locale).to eq("ja")
    end
  end
end
