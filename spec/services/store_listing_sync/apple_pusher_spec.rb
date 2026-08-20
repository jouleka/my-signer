require "rails_helper"

RSpec.describe StoreListingSync::ApplePusher do
  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) {
    create(:apple_app, organization: organization, app_store_id: "9991", bundle_id: "com.test.pusher")
  }
  let!(:credential) {
    create(:app_store_connect_credential, organization: organization, active: true)
  }
  let(:store_listing) {
    create(:store_listing, :ios,
      organization: organization,
      listable: apple_app,
      locale: "en-GB",
      app_name: "Test App",
      subtitle: "A test",
      description: "Long description here",
      keywords: "test,app",
      whats_new: "What's new in this version",
      promotional_text: "Try it!",
      support_url: "https://support.test",
      marketing_url: "https://marketing.test"
    )
  }

  let(:mock_client) { instance_double(AppStoreConnect::Client) }
  let(:mock_app_info) { instance_double(AppStoreConnect::AppInfo) }
  let(:mock_versions) { instance_double(AppStoreConnect::Versions) }

  before do
    allow(AppStoreConnect::Client).to receive(:new).and_return(mock_client)
    allow(AppStoreConnect::AppInfo).to receive(:new).and_return(mock_app_info)
    allow(AppStoreConnect::Versions).to receive(:new).and_return(mock_versions)

    # Default: no editable version (the READY_FOR_SALE / live-app scenario)
    allow(mock_versions).to receive(:editable_versions).and_return([])
  end

  describe "#push_app_info!" do
    context "when Apple accepts both name and subtitle" do
      it "calls update_by_locale once and does not skip any fields" do
        expect(mock_app_info).to receive(:update_by_locale).with(
          app_id: apple_app.app_store_id,
          locale: "en-GB",
          name: "Test App",
          subtitle: "A test"
        ).once

        result = described_class.new(organization: organization, store_listing: store_listing).push!

        expect(result[:skipped_fields]).not_to include("name", "subtitle")
      end
    end

    context "when Apple rejects 'name' but accepts 'subtitle'" do
      it "retries without name and marks name as skipped" do
        # First call: Apple rejects 'name'
        # Second call: only subtitle remains, succeeds
        call_count = 0
        allow(mock_app_info).to receive(:update_by_locale) do |args|
          call_count += 1
          if call_count == 1 && args[:name]
            raise StandardError, "There is a problem with the request entity: The field 'name' can not be modified in the current state."
          end
        end

        result = described_class.new(organization: organization, store_listing: store_listing).push!

        expect(call_count).to eq(2)
        expect(result[:skipped_fields]).to include("name")
        expect(result[:skipped_fields]).not_to include("subtitle")
      end
    end

    context "when Apple rejects both 'name' and 'subtitle'" do
      it "skips both fields and does not blow up the entire push" do
        allow(mock_app_info).to receive(:update_by_locale) do |args|
          if args[:name]
            raise StandardError, "There is a problem with the request entity: The field 'name' can not be modified in the current state."
          elsif args[:subtitle]
            raise StandardError, "There is a problem with the request entity: The field 'subtitle' can not be modified in the current state."
          end
          # Empty attrs hash never reaches here because the recursive call returns early
        end

        result = nil
        expect {
          result = described_class.new(organization: organization, store_listing: store_listing).push!
        }.not_to raise_error

        expect(result[:skipped_fields]).to include("name", "subtitle")
        expect(store_listing.reload.push_status).to eq("partial_success")
      end
    end

    context "when Apple raises an unrelated error" do
      it "re-raises so the job records it as a real failure" do
        allow(mock_app_info).to receive(:update_by_locale).and_raise(StandardError, "Unauthorized: invalid JWT")

        expect {
          described_class.new(organization: organization, store_listing: store_listing).push!
        }.to raise_error(StandardError, /Unauthorized/)
      end
    end

    context "when both name and subtitle are blank" do
      let(:store_listing) {
        create(:store_listing, :ios,
          organization: organization, listable: apple_app, locale: "en-GB",
          app_name: nil, subtitle: nil)
      }

      it "does not call Apple at all" do
        expect(mock_app_info).not_to receive(:update_by_locale)

        described_class.new(organization: organization, store_listing: store_listing).push!
      end
    end
  end

  describe "the live READY_FOR_SALE scenario (the bug we just fixed)" do
    it "marks name and subtitle as skipped, and continues to push promotional_text" do
      # Apple rejects both name and subtitle during app-info push
      call_count = 0
      allow(mock_app_info).to receive(:update_by_locale) do |args|
        call_count += 1
        if args[:name]
          raise StandardError, "There is a problem with the request entity: The field 'name' can not be modified in the current state."
        elsif args[:subtitle]
          raise StandardError, "There is a problem with the request entity: The field 'subtitle' can not be modified in the current state."
        end
      end

      result = nil
      expect {
        result = described_class.new(organization: organization, store_listing: store_listing).push!
      }.not_to raise_error

      # name and subtitle should be in skipped_fields
      expect(result[:skipped_fields]).to include("name", "subtitle")
      # The push should NOT have crashed entirely
      expect(store_listing.reload.push_status).to eq("partial_success")
      expect(store_listing.push_error).to be_nil
    end
  end
end
