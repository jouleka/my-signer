require "rails_helper"

RSpec.describe ReleaseNotes::ConversionHints do
  describe ".analyze" do
    it "returns empty array for iOS platform" do
      text = "Bugs were fixed and various improvements were made."
      result = described_class.analyze(text, platform: :ios)
      expect(result).to eq([])
    end

    it "returns empty array for blank text" do
      result = described_class.analyze("", platform: :android)
      expect(result).to eq([])
    end

    it "returns empty array for nil text" do
      result = described_class.analyze(nil, platform: :android)
      expect(result).to eq([])
    end

    describe "passive voice detection" do
      it "detects 'was fixed' passive voice" do
        text = "A bug was fixed in the login flow."
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).to include("active_voice")
      end

      it "detects 'were updated' passive voice" do
        text = "Settings were updated for better performance."
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).to include("active_voice")
      end

      it "does not flag active voice text" do
        text = "We fixed the crash bug and improved performance."
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).not_to include("active_voice")
      end
    end

    describe "vague language detection" do
      it "detects 'various' as vague language" do
        text = "Various improvements and updates."
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).to include("specifics_over_vague")
      end

      it "detects 'several' as vague language" do
        text = "Several bugs have been addressed."
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).to include("specifics_over_vague")
      end

      it "detects 'minor fix' as vague language" do
        text = "Minor fixes applied to the app."
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).to include("specifics_over_vague")
      end

      it "does not flag specific language" do
        text = "App launches 40% faster. Dark mode added."
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).not_to include("specifics_over_vague")
      end
    end

    describe "length warning" do
      it "warns when text exceeds 400 characters" do
        text = "A" * 401
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).to include("length_warning")
      end

      it "does not warn when text is under 400 characters" do
        text = "A" * 400
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).not_to include("length_warning")
      end
    end

    describe "hint object structure" do
      it "returns correct hint structure" do
        text = "A bug was fixed."
        result = described_class.analyze(text, platform: :android)

        hint = result.first
        expect(hint).to have_key(:key)
        expect(hint).to have_key(:label)
        expect(hint).to have_key(:description)
        expect(hint).to have_key(:example)
      end
    end

    describe "multiple hints" do
      it "returns multiple hints when multiple issues detected" do
        text = "Various bugs were fixed. " + ("A" * 400)
        result = described_class.analyze(text, platform: :android)

        keys = result.map { |h| h[:key] }
        expect(keys).to include("active_voice")
        expect(keys).to include("specifics_over_vague")
        expect(keys).to include("length_warning")
      end
    end
  end
end
