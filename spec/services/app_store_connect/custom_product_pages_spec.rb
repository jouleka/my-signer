require "rails_helper"

RSpec.describe AppStoreConnect::CustomProductPages do
  let(:client) { instance_double(AppStoreConnect::Client) }
  let(:service) { described_class.new(client) }

  describe "#list" do
    it "paginates appCustomProductPages for an app" do
      expect(client).to receive(:paginate).with(
        "apps/APP123/appCustomProductPages",
        params: { "fields[appCustomProductPages]" => "name,url,visible" }
      )

      service.list(app_id: "APP123")
    end

    it "yields each page to the block" do
      page_data = { "data" => [ { "id" => "cpp1" } ] }
      allow(client).to receive(:paginate).and_yield(page_data)

      yielded = []
      service.list(app_id: "APP123") { |page| yielded << page }

      expect(yielded).to eq([ page_data ])
    end
  end

  describe "#create" do
    it "posts a CPP with inline version and localization" do
      expect(client).to receive(:post) do |path, json:|
        expect(path).to eq("appCustomProductPages")
        expect(json[:data][:attributes][:name]).to eq("Summer Campaign")
        expect(json[:data][:relationships][:app][:data][:id]).to eq("APP123")
        expect(json[:data][:relationships][:appCustomProductPageVersions]).to be_present
        expect(json[:included]).to be_an(Array)
        expect(json[:included].size).to eq(2)

        version = json[:included].find { |i| i[:type] == "appCustomProductPageVersions" }
        expect(version).to be_present

        localization = json[:included].find { |i| i[:type] == "appCustomProductPageLocalizations" }
        expect(localization).to be_present
        expect(localization[:attributes][:locale]).to eq("en-US")
      end

      service.create(app_id: "APP123", name: "Summer Campaign", locale: "en-US")
    end

    it "includes appStoreVersionTemplate when provided" do
      expect(client).to receive(:post) do |_path, json:|
        expect(json[:data][:relationships][:appStoreVersionTemplate][:data][:id]).to eq("VERSION_1")
      end

      service.create(app_id: "APP123", name: "Promo", locale: "en-US", app_store_version_id: "VERSION_1")
    end
  end

  describe "#update" do
    it "patches CPP attributes" do
      expected_payload = {
        data: {
          type: "appCustomProductPages",
          id: "CPP123",
          attributes: { name: "Updated Name", visible: false }
        }
      }

      expect(client).to receive(:patch).with("appCustomProductPages/CPP123", json: expected_payload)

      service.update(cpp_id: "CPP123", name: "Updated Name", visible: false)
    end

    it "only includes provided attributes" do
      expected_payload = {
        data: {
          type: "appCustomProductPages",
          id: "CPP123",
          attributes: { name: "New Name" }
        }
      }

      expect(client).to receive(:patch).with("appCustomProductPages/CPP123", json: expected_payload)

      service.update(cpp_id: "CPP123", name: "New Name")
    end
  end

  describe "#delete" do
    it "deletes a CPP" do
      expect(client).to receive(:delete).with("appCustomProductPages/CPP123")

      service.delete(cpp_id: "CPP123")
    end
  end

  describe "#versions" do
    it "gets versions for a CPP" do
      expect(client).to receive(:get).with("appCustomProductPages/CPP123/appCustomProductPageVersions")

      service.versions(cpp_id: "CPP123")
    end
  end

  describe "#localizations" do
    it "gets localizations for a version" do
      expect(client).to receive(:get).with("appCustomProductPageVersions/VER123/appCustomProductPageLocalizations")

      service.localizations(version_id: "VER123")
    end
  end

  describe "#create_localization" do
    it "posts a new localization" do
      expected_payload = {
        data: {
          type: "appCustomProductPageLocalizations",
          attributes: { locale: "en-US", promotionalText: "Summer deals!" },
          relationships: {
            appCustomProductPageVersion: {
              data: { type: "appCustomProductPageVersions", id: "VER123" }
            }
          }
        }
      }

      expect(client).to receive(:post).with("appCustomProductPageLocalizations", json: expected_payload)

      service.create_localization(version_id: "VER123", locale: "en-US", promotional_text: "Summer deals!")
    end
  end

  describe "#update_localization" do
    it "patches a localization" do
      expected_payload = {
        data: {
          type: "appCustomProductPageLocalizations",
          id: "LOC123",
          attributes: { promotionalText: "Updated text" }
        }
      }

      expect(client).to receive(:patch).with("appCustomProductPageLocalizations/LOC123", json: expected_payload)

      service.update_localization(localization_id: "LOC123", promotional_text: "Updated text")
    end
  end

  describe "#update_version" do
    it "patches a version with deep link" do
      expected_payload = {
        data: {
          type: "appCustomProductPageVersions",
          id: "VER123",
          attributes: { deepLink: "myapp://promo/summer" }
        }
      }

      expect(client).to receive(:patch).with("appCustomProductPageVersions/VER123", json: expected_payload)

      service.update_version(version_id: "VER123", deep_link: "myapp://promo/summer")
    end

    it "sends empty attributes when deep_link is nil" do
      expected_payload = {
        data: {
          type: "appCustomProductPageVersions",
          id: "VER123",
          attributes: {}
        }
      }

      expect(client).to receive(:patch).with("appCustomProductPageVersions/VER123", json: expected_payload)

      service.update_version(version_id: "VER123")
    end
  end

  describe "#screenshot_sets" do
    it "gets screenshot sets for a localization" do
      expect(client).to receive(:get).with("appCustomProductPageLocalizations/LOC123/appScreenshotSets")

      service.screenshot_sets(localization_id: "LOC123")
    end
  end

  describe "#available_keywords" do
    it "fetches keywords for an app" do
      expect(client).to receive(:get)
        .with("apps/APP123/searchKeywords", params: { "filter[locale]" => "en-US" })
        .and_return({ "data" => [] })

      service.available_keywords(app_id: "APP123", locale: "en-US")
    end
  end

  describe "#keywords" do
    it "gets assigned keywords for a localization" do
      expect(client).to receive(:get)
        .with("appCustomProductPageLocalizations/LOC123/searchKeywords")
        .and_return({ "data" => [] })

      service.keywords(localization_id: "LOC123")
    end
  end

  describe "#add_keywords" do
    it "links keywords to a localization" do
      expected_payload = {
        data: [ { type: "appKeywords", id: "KW1" }, { type: "appKeywords", id: "KW2" } ]
      }

      expect(client).to receive(:post)
        .with("appCustomProductPageLocalizations/LOC123/relationships/searchKeywords", json: expected_payload)

      service.add_keywords(localization_id: "LOC123", keyword_ids: [ "KW1", "KW2" ])
    end
  end

  describe "#remove_keywords" do
    it "unlinks keywords from a localization" do
      expected_payload = {
        data: [ { type: "appKeywords", id: "KW1" } ]
      }

      expect(client).to receive(:delete_with_body)
        .with("appCustomProductPageLocalizations/LOC123/relationships/searchKeywords", json: expected_payload)

      service.remove_keywords(localization_id: "LOC123", keyword_ids: [ "KW1" ])
    end
  end

  describe "#submit_for_review" do
    it "executes the 3-step unified review submission flow" do
      # Step 1: Create review submission
      expect(client).to receive(:post).with("reviewSubmissions", json: {
        data: {
          type: "reviewSubmissions",
          attributes: { platform: "IOS" },
          relationships: {
            app: { data: { type: "apps", id: "APP123" } }
          }
        }
      }).and_return({ "data" => { "id" => "RS_001" } }).ordered

      # Step 2: Add CPP version as review item
      expect(client).to receive(:post).with("reviewSubmissionItems", json: {
        data: {
          type: "reviewSubmissionItems",
          relationships: {
            reviewSubmission: { data: { type: "reviewSubmissions", id: "RS_001" } },
            appCustomProductPageVersion: { data: { type: "appCustomProductPageVersions", id: "CPPV_001" } }
          }
        }
      }).ordered

      # Step 3: Submit for review
      expect(client).to receive(:patch).with("reviewSubmissions/RS_001", json: {
        data: {
          type: "reviewSubmissions",
          id: "RS_001",
          attributes: { submitted: true }
        }
      }).ordered

      service.submit_for_review(app_id: "APP123", cpp_version_id: "CPPV_001")
    end

    it "uses the submission ID from step 1 in subsequent steps" do
      allow(client).to receive(:post).with("reviewSubmissions", anything)
        .and_return({ "data" => { "id" => "RS_CUSTOM_ID" } })

      expect(client).to receive(:post).with("reviewSubmissionItems", json: hash_including(
        data: hash_including(
          relationships: hash_including(
            reviewSubmission: { data: { type: "reviewSubmissions", id: "RS_CUSTOM_ID" } }
          )
        )
      ))

      expect(client).to receive(:patch).with("reviewSubmissions/RS_CUSTOM_ID", anything)

      service.submit_for_review(app_id: "APP123", cpp_version_id: "CPPV_001")
    end

    it "raises if the first API call fails" do
      allow(client).to receive(:post).with("reviewSubmissions", anything)
        .and_raise(StandardError, "CONFLICT")

      expect {
        service.submit_for_review(app_id: "APP123", cpp_version_id: "CPPV_001")
      }.to raise_error(StandardError, "CONFLICT")
    end
  end
end
