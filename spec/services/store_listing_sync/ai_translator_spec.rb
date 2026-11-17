require "rails_helper"

RSpec.describe StoreListingSync::AiTranslator do
  describe "#translate!" do
    let(:organization) { create(:organization) }
    let(:app) { create(:apple_app, organization: organization) }
    let(:source) { create(:store_listing, organization: organization, listable: app, description: "Opening " + "detail " * 100 + "THE END") }
    let(:target) { create(:store_listing, organization: organization, listable: app, locale: "de-DE", app_name: "Keep Brand", description: "My draft") }
    let(:client) { instance_double(OpenAI::Client) }
    let(:translator) { described_class.new(base_listing: source, target_listing: target, fields: [ :description ]) }

    before { allow_any_instance_of(described_class).to receive(:build_client).and_return(client) }

    def response_for(value)
      { "choices" => [ { "message" => { "content" => value.to_json } } ] }
    end

    it "sends the full source and updates only the requested field" do
      expect(client).to receive(:chat) do |parameters:|
        expect(parameters[:messages].last[:content]).to include(source.description)
        response_for("description" => "Vollständiger Text", "app_name" => "Unrequested Brand")
      end
      translator.translate!
      expect(target.reload.description).to eq("Vollständiger Text")
      expect(target.app_name).to eq("Keep Brand")
      expect(target.translation_status).to eq("needs_review")
    end

    [ [], {}, { "description" => nil }, { "description" => " " } ].each do |invalid|
      it "rejects incomplete or malformed translation #{invalid.inspect} without changing the draft" do
        allow(client).to receive(:chat).and_return(response_for(invalid))
        expect { translator.translate! }.to raise_error(/Translation failed/)
        expect(target.reload.description).to eq("My draft")
        expect(target.translation_status).to be_nil
      end
    end

    it "preserves an edit made while the translation request is running" do
      allow(client).to receive(:chat) do
        target.class.find(target.id).update!(description: "Newer manual edit")
        response_for("description" => "Delayed translation")
      end
      expect { translator.translate! }.to raise_error(/changed while/)
      expect(target.reload.description).to eq("Newer manual edit")
    end
  end

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
      it "fits translated keywords within Apple's UTF-8 byte limit" do
        source = "検索,写真,編集,動画,翻訳,共有,保存,音声,画像,旅行,旅行計画,撮影,休日,地図,連絡"
        expect(source.bytesize).to be > 100
        result = described_class.enforce_char_limit(:keywords, source, 100)
        expect(result.bytesize).to be <= 100
        expect(result).not_to end_with(",")
      end

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
