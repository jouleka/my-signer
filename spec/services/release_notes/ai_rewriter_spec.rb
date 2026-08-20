require "rails_helper"

RSpec.describe ReleaseNotes::AiRewriter do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:android_app) { create(:android_app, organization: organization) }
  let(:release_note) { create(:release_note, organization: organization, listable: apple_app) }
  let(:raw_input) { "fix: resolved crash in photo picker\nfeat: add dark theme support\nperf: optimize image loading" }

  let(:mock_client) { instance_double(OpenAI::Client) }

  let(:ai_response) do
    {
      "choices" => [
        {
          "message" => {
            "content" => {
              "new" => [ "Dark theme support is here" ],
              "improved" => [ "Faster image loading" ],
              "fixed" => [ "Resolved crash in photo picker" ],
              "rendered_text" => "NEW\n- Dark theme support is here\n\nIMPROVED\n- Faster image loading\n\nFIXED\n- Resolved crash in photo picker"
            }.to_json
          }
        }
      ]
    }
  end

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_client)
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("test-key")
  end

  describe "#rewrite!" do
    it "calls OpenAI with correct parameters" do
      allow(mock_client).to receive(:chat).and_return(ai_response)

      described_class.new(release_note: release_note, raw_input: raw_input).rewrite!

      expect(mock_client).to have_received(:chat).with(
        parameters: hash_including(
          model: "gpt-5-nano",
          response_format: { type: "json_object" }
        )
      )
    end

    it "includes system prompt and user prompt with platform info" do
      allow(mock_client).to receive(:chat) do |params|
        messages = params[:parameters][:messages]
        system_msg = messages.find { |m| m[:role] == "system" }
        user_msg = messages.find { |m| m[:role] == "user" }

        expect(system_msg[:content]).to include("expert mobile app copywriter")
        expect(user_msg[:content]).to include("iOS App Store")
        expect(user_msg[:content]).to include("4000")
        expect(user_msg[:content]).to include(raw_input)

        ai_response
      end

      described_class.new(release_note: release_note, raw_input: raw_input).rewrite!
    end

    it "includes Android platform info for Android apps" do
      android_note = create(:release_note, :android, organization: organization, listable: android_app)

      allow(mock_client).to receive(:chat) do |params|
        messages = params[:parameters][:messages]
        user_msg = messages.find { |m| m[:role] == "user" }

        expect(user_msg[:content]).to include("Google Play Store")
        expect(user_msg[:content]).to include("500")

        ai_response
      end

      described_class.new(release_note: android_note, raw_input: raw_input).rewrite!
    end

    it "parses response and updates the release note" do
      allow(mock_client).to receive(:chat).and_return(ai_response)

      result = described_class.new(release_note: release_note, raw_input: raw_input).rewrite!

      expect(result).to be_a(Hash)
      expect(result["new"]).to include("Dark theme support is here")
      expect(result["improved"]).to include("Faster image loading")
      expect(result["fixed"]).to include("Resolved crash in photo picker")
    end

    it "applies rewrite to the release note" do
      allow(mock_client).to receive(:chat).and_return(ai_response)

      described_class.new(release_note: release_note, raw_input: raw_input).rewrite!

      release_note.reload
      expect(release_note.source).to eq("ai_rewrite")
      expect(release_note.raw_input).to eq(raw_input)
      expect(release_note.template_data).to include("new" => [ "Dark theme support is here" ])
      expect(release_note.rendered_text).to include("NEW\n- Dark theme support is here")
    end
  end

  describe "error handling" do
    it "raises on JSON parse error" do
      bad_response = {
        "choices" => [ { "message" => { "content" => "not valid json {{{" } } ]
      }
      allow(mock_client).to receive(:chat).and_return(bad_response)

      expect {
        described_class.new(release_note: release_note, raw_input: raw_input).rewrite!
      }.to raise_error("Rewrite failed: could not parse AI response")
    end

    it "raises on API error" do
      allow(mock_client).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("connection refused"))

      expect {
        described_class.new(release_note: release_note, raw_input: raw_input).rewrite!
      }.to raise_error(/Rewrite failed/)
    end

    it "raises when API key is not configured" do
      allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return(nil)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)

      expect {
        described_class.new(release_note: release_note, raw_input: raw_input)
      }.to raise_error("OpenAI API key not configured")
    end
  end

  describe "character limits" do
    it "passes iOS char limit of 4000 in the prompt" do
      allow(mock_client).to receive(:chat) do |params|
        user_msg = params[:parameters][:messages].find { |m| m[:role] == "user" }
        expect(user_msg[:content]).to include("4000")
        ai_response
      end

      described_class.new(release_note: release_note, raw_input: raw_input).rewrite!
    end

    it "passes Android char limit of 500 in the prompt" do
      android_note = create(:release_note, :android, organization: organization, listable: android_app)

      allow(mock_client).to receive(:chat) do |params|
        user_msg = params[:parameters][:messages].find { |m| m[:role] == "user" }
        expect(user_msg[:content]).to include("500")
        ai_response
      end

      described_class.new(release_note: android_note, raw_input: raw_input).rewrite!
    end

    it "truncates raw_input to 2000 characters" do
      long_input = "a" * 3000

      allow(mock_client).to receive(:chat) do |params|
        user_msg = params[:parameters][:messages].find { |m| m[:role] == "user" }
        # The raw input in the prompt should be truncated to 2000 chars
        expect(user_msg[:content]).not_to include("a" * 2001)
        ai_response
      end

      described_class.new(release_note: release_note, raw_input: long_input).rewrite!
    end
  end
end
