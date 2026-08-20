require "rails_helper"

RSpec.describe AppStoreConnect::Versions do
  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  let(:service) { described_class.new(mock_client) }

  describe "#find_open_review_submission" do
    it "returns the first open submission when one exists" do
      response = {
        "data" => [
          {
            "id" => "rs-existing-1",
            "type" => "reviewSubmissions",
            "attributes" => { "state" => "READY_FOR_REVIEW", "platform" => "IOS" }
          }
        ]
      }
      expect(mock_client).to receive(:get)
        .with("apps/123/reviewSubmissions", params: hash_including(
          "filter[platform]" => "IOS",
          "filter[state]" => "READY_FOR_REVIEW"
        ))
        .and_return(response)

      result = service.find_open_review_submission(app_id: "123")
      expect(result).to be_a(Hash)
      expect(result["id"]).to eq("rs-existing-1")
    end

    it "returns nil when no open submission exists" do
      expect(mock_client).to receive(:get).and_return({ "data" => [] })

      expect(service.find_open_review_submission(app_id: "123")).to be_nil
    end

    it "returns nil when Apple errors (does not raise)" do
      allow(Rails.logger).to receive(:warn)
      expect(mock_client).to receive(:get).and_raise(StandardError, "HTTP 500")

      expect(service.find_open_review_submission(app_id: "123")).to be_nil
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/find_open_review_submission/))
    end
  end

  describe "#submit_for_review" do
    context "when no open draft exists" do
      it "creates a new reviewSubmission, adds an item, and PATCHes submitted:true" do
        expect(mock_client).to receive(:get)
          .with("apps/123/reviewSubmissions", params: anything)
          .and_return({ "data" => [] })

        expect(mock_client).to receive(:post)
          .with("reviewSubmissions", json: hash_including(data: hash_including(type: "reviewSubmissions")))
          .and_return({ "data" => { "id" => "rs-new-1", "type" => "reviewSubmissions" } })

        expect(mock_client).to receive(:post)
          .with("reviewSubmissionItems", json: hash_including(
            data: hash_including(type: "reviewSubmissionItems")
          ))
          .and_return({ "data" => { "id" => "rsi-1" } })

        expect(mock_client).to receive(:patch)
          .with("reviewSubmissions/rs-new-1", json: hash_including(
            data: hash_including(attributes: { submitted: true })
          ))
          .and_return({ "data" => {} })

        result = service.submit_for_review(app_id: "123", version_id: "v-456")
        expect(result["submission_id"]).to eq("rs-new-1")
        expect(result["reused"]).to be(false)
      end
    end

    context "when an open draft already exists for this app" do
      let(:existing_submission) do
        {
          "id" => "rs-existing-1",
          "type" => "reviewSubmissions",
          "attributes" => { "state" => "READY_FOR_REVIEW", "platform" => "IOS" }
        }
      end

      it "reuses the existing submission and does NOT POST a new one" do
        expect(mock_client).to receive(:get)
          .with("apps/123/reviewSubmissions", params: anything)
          .and_return({ "data" => [ existing_submission ] })

        # existing draft has no items yet
        expect(mock_client).to receive(:get)
          .with("reviewSubmissions/rs-existing-1/items")
          .and_return({ "data" => [] })

        # NO POST to reviewSubmissions — the key assertion
        expect(mock_client).not_to receive(:post).with("reviewSubmissions", anything)

        expect(mock_client).to receive(:post)
          .with("reviewSubmissionItems", json: anything)
          .and_return({ "data" => { "id" => "rsi-2" } })

        expect(mock_client).to receive(:patch)
          .with("reviewSubmissions/rs-existing-1", json: hash_including(
            data: hash_including(attributes: { submitted: true })
          ))
          .and_return({ "data" => {} })

        result = service.submit_for_review(app_id: "123", version_id: "v-456")
        expect(result["submission_id"]).to eq("rs-existing-1")
        expect(result["reused"]).to be(true)
      end

      it "skips item creation when the version is already attached to the draft" do
        expect(mock_client).to receive(:get)
          .with("apps/123/reviewSubmissions", params: anything)
          .and_return({ "data" => [ existing_submission ] })

        # Draft already has this version as an item
        expect(mock_client).to receive(:get)
          .with("reviewSubmissions/rs-existing-1/items")
          .and_return({
            "data" => [
              {
                "id" => "rsi-existing",
                "type" => "reviewSubmissionItems",
                "relationships" => {
                  "appStoreVersion" => { "data" => { "type" => "appStoreVersions", "id" => "v-456" } }
                }
              }
            ]
          })

        # No POST to reviewSubmissionItems this time
        expect(mock_client).not_to receive(:post)

        expect(mock_client).to receive(:patch)
          .with("reviewSubmissions/rs-existing-1", json: anything)
          .and_return({ "data" => {} })

        result = service.submit_for_review(app_id: "123", version_id: "v-456")
        expect(result["reused"]).to be(true)
      end
    end
  end

  describe "#update_release_settings" do
    it "PATCHes the version with releaseType only when release_type is MANUAL" do
      expect(mock_client).to receive(:patch)
        .with("appStoreVersions/v-456", json: hash_including(
          data: hash_including(
            id: "v-456",
            attributes: { releaseType: "MANUAL" }
          )
        ))
        .and_return({ "data" => {} })

      service.update_release_settings(version_id: "v-456", release_type: "MANUAL")
    end

    it "PATCHes with releaseType + earliestReleaseDate when SCHEDULED" do
      scheduled = 2.days.from_now
      expect(mock_client).to receive(:patch) do |path, json:|
        expect(path).to eq("appStoreVersions/v-456")
        attrs = json.dig(:data, :attributes)
        expect(attrs[:releaseType]).to eq("SCHEDULED")
        expect(attrs[:earliestReleaseDate]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
        { "data" => {} }
      end

      service.update_release_settings(
        version_id: "v-456",
        release_type: "SCHEDULED",
        earliest_release_date: scheduled
      )
    end

    it "accepts an ISO string for earliest_release_date" do
      scheduled_iso = 2.days.from_now.utc.iso8601
      expect(mock_client).to receive(:patch).and_return({ "data" => {} })

      service.update_release_settings(
        version_id: "v-456",
        release_type: "SCHEDULED",
        earliest_release_date: scheduled_iso
      )
    end
  end
end
