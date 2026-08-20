require "rails_helper"

RSpec.describe StoreListingSync::AiTranslator do
  describe ".enforce_char_limit" do
    context "with a regular free-text field" do
      it "returns text unchanged when under the limit" do
        expect(described_class.enforce_char_limit(:app_name, "Short name", 30))
          .to eq("Short name")
      end

      it "truncates free text at the limit" do
        long = "a" * 50
        expect(described_class.enforce_char_limit(:app_name, long, 30))
          .to eq("a" * 30)
      end

      it "returns text unchanged when limit is nil" do
        expect(described_class.enforce_char_limit(:app_name, "whatever", nil))
          .to eq("whatever")
      end
    end

    context "with the keywords field" do
      it "returns unchanged when under the limit" do
        kw = "a,b,c"
        expect(described_class.enforce_char_limit(:keywords, kw, 100)).to eq(kw)
      end

      it "keeps whole comma-separated terms that fit and drops the rest" do
        # German expansion example: original English 99 chars → German 112 chars.
        over = "Rechenschaftspflicht,Gewohnheiten,Ziele,Motivation,Versprechen," \
               "Einsätze,Geld,Wette,Selbstverbesserung,Disziplin,Serie"
        expect(over.length).to be > 100

        result = described_class.enforce_char_limit(:keywords, over, 100)

        expect(result.length).to be <= 100
        # Every kept term must be a whole term from the original (no mid-word cuts).
        result.split(",").each do |term|
          expect(over.split(",").map(&:strip)).to include(term)
        end
      end

      it "handles the edge case where even the first term is too long" do
        # If the AI returns one huge "keyword", no whole term fits — return "".
        result = described_class.enforce_char_limit(:keywords, "a" * 200, 100)
        expect(result).to eq("")
      end
    end
  end
end
