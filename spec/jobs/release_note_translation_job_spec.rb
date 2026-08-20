require "rails_helper"

RSpec.describe ReleaseNoteTranslationJob, type: :job do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:release_note) do
    create(:release_note,
      organization: organization,
      listable: apple_app,
      locale: "en-US",
      rendered_text: "NEW\n- Dark mode\n\nFIXED\n- Crash on startup"
    )
  end

  let(:mock_client) { instance_double(OpenAI::Client) }

  before do
    # Pre-set the reset timestamp to avoid dirty attributes from monthly reset logic
    organization.update_columns(ai_translations_count: 0, ai_translations_reset_at: Time.current)
    allow(OpenAI::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:chat)
    allow(Rails.application.credentials).to receive(:dig).with(:openai, :api_key).and_return("test-key")
  end

  def mock_translation_response(translated_text)
    {
      "choices" => [
        {
          "message" => {
            "content" => { "translated_text" => translated_text }.to_json
          }
        }
      ]
    }
  end

  describe "#perform" do
    context "with target locales" do
      let!(:de_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "de-DE")
      end
      let!(:ja_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "ja")
      end
      let!(:en_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "en-US")
      end

      it "translates to all other locales" do
        allow(mock_client).to receive(:chat)
          .and_return(
            mock_translation_response("NEU\n- Dunkelmodus"),
            mock_translation_response("NEW\n- ダークモード")
          )

        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id
        )

        expect(mock_client).to have_received(:chat).twice
      end

      it "stores translations in the release note JSONB" do
        allow(mock_client).to receive(:chat)
          .and_return(
            mock_translation_response("NEU\n- Dunkelmodus"),
            mock_translation_response("NEW\n- ダークモード")
          )

        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id
        )

        release_note.reload
        expect(release_note.translations).to be_a(Hash)
        expect(release_note.translations.keys).to include("de-DE", "ja")
        expect(release_note.translations["de-DE"]).to eq("NEU\n- Dunkelmodus")
        expect(release_note.translations["ja"]).to eq("NEW\n- ダークモード")
      end

      it "increments ai_translations_count per locale" do
        allow(mock_client).to receive(:chat)
          .and_return(
            mock_translation_response("NEU\n- Dunkelmodus"),
            mock_translation_response("NEW\n- ダークモード")
          )

        expect {
          described_class.perform_now(
            organization_id: organization.id,
            release_note_id: release_note.id
          )
        }.to change { organization.reload.ai_translations_count }.by(2)
      end
    end

    context "quota checking per locale" do
      let!(:de_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "de-DE")
      end
      let!(:ja_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "ja")
      end
      let!(:en_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "en-US")
      end

      it "skips locales when quota is exhausted mid-run" do
        # Set quota to 1 remaining
        organization.update_columns(ai_translations_count: 99, ai_translations_reset_at: Time.current)

        allow(mock_client).to receive(:chat)
          .and_return(mock_translation_response("NEU\n- Dunkelmodus"))

        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id
        )

        # Only one translation should have been performed (quota was 1)
        expect(mock_client).to have_received(:chat).once
      end
    end

    context "per-locale failure handling" do
      let!(:de_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "de-DE")
      end
      let!(:ja_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "ja")
      end
      let!(:en_listing) do
        create(:store_listing, organization: organization, listable: apple_app, locale: "en-US")
      end

      it "continues with other locales when one fails" do
        call_count = 0
        allow(mock_client).to receive(:chat) do
          call_count += 1
          if call_count == 1
            raise Faraday::ConnectionFailed, "connection refused"
          else
            mock_translation_response("NEW\n- ダークモード")
          end
        end

        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id
        )

        release_note.reload
        expect(release_note.translations).to be_a(Hash)
        expect(release_note.translations.values).to include("NEW\n- ダークモード")
      end

      it "refunds quota for failed locale translations" do
        allow(mock_client).to receive(:chat)
          .and_raise(Faraday::ConnectionFailed, "connection refused")

        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id
        )

        # Each locale's quota was incremented then refunded
        expect(organization.reload.ai_translations_count).to eq(0)
      end

      it "refunds all charged quota when the final persist fails (L-16)" do
        allow(mock_client).to receive(:chat)
          .and_return(
            mock_translation_response("NEU\n- Dunkelmodus"),
            mock_translation_response("NEW\n- ダークモード")
          )
        # Both locales translate successfully (quota charged x2), but the final
        # release_note.update! blows up — every charged-but-unpersisted unit
        # must be refunded rather than leaked.
        allow_any_instance_of(ReleaseNote).to receive(:update!)
          .and_raise(ActiveRecord::RecordInvalid.new(release_note))

        expect {
          described_class.perform_now(
            organization_id: organization.id,
            release_note_id: release_note.id
          )
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(organization.reload.ai_translations_count).to eq(0)
      end
    end

    context "when no target locales exist" do
      it "returns without translating" do
        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: release_note.id
        )

        expect(mock_client).not_to have_received(:chat)
      end
    end

    context "when rendered_text is blank" do
      let(:blank_note) do
        create(:release_note,
          organization: organization,
          listable: apple_app,
          locale: "en-US",
          rendered_text: "",
          template_data: {}
        )
      end

      it "returns without translating" do
        create(:store_listing, organization: organization, listable: apple_app, locale: "de-DE")

        described_class.perform_now(
          organization_id: organization.id,
          release_note_id: blank_note.id
        )

        expect(mock_client).not_to have_received(:chat)
      end
    end

    context "when records not found" do
      it "returns silently when organization not found" do
        expect {
          described_class.perform_now(
            organization_id: -1,
            release_note_id: release_note.id
          )
        }.not_to raise_error

        expect(mock_client).not_to have_received(:chat)
      end

      it "returns silently when release note not found" do
        expect {
          described_class.perform_now(
            organization_id: organization.id,
            release_note_id: -1
          )
        }.not_to raise_error

        expect(mock_client).not_to have_received(:chat)
      end
    end

    it "enqueues the job" do
      expect {
        described_class.perform_later(
          organization_id: organization.id,
          release_note_id: release_note.id
        )
      }.to have_enqueued_job(described_class)
    end
  end
end
