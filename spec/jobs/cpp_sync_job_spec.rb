require "rails_helper"

RSpec.describe CppSyncJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:credential) { create(:app_store_connect_credential, organization: organization) }
  let(:apple_app) { create(:apple_app, organization: organization) }

  let(:client) { instance_double(AppStoreConnect::Client) }
  let(:service) { instance_double(AppStoreConnect::CustomProductPages) }

  before do
    credential
    apple_app

    allow(AppStoreConnect::Client).to receive(:new).and_return(client)
    allow(AppStoreConnect::CustomProductPages).to receive(:new).and_return(service)
  end

  describe "#perform" do
    it "syncs CPPs from Apple API" do
      cpp_page = {
        "data" => [
          {
            "id" => "cpp_remote_1",
            "attributes" => { "name" => "Summer Campaign", "visible" => true }
          }
        ],
        "links" => {}
      }

      version_response = {
        "data" => [
          {
            "id" => "ver_remote_1",
            "attributes" => { "state" => "PUBLISHED" }
          }
        ]
      }

      localization_response = {
        "data" => [
          {
            "id" => "loc_remote_1",
            "attributes" => { "locale" => "en-US", "promotionalText" => "Summer deals!" }
          }
        ]
      }

      allow(service).to receive(:list) do |app_id:, &block|
        block.call(cpp_page)
      end
      allow(service).to receive(:versions).and_return(version_response)
      allow(service).to receive(:localizations).and_return(localization_response)

      described_class.perform_now(organization_id: organization.id)

      expect(organization.custom_product_pages.count).to eq(1)
      cpp = organization.custom_product_pages.first
      expect(cpp.name).to eq("Summer Campaign")
      expect(cpp.remote_id).to eq("cpp_remote_1")
      expect(cpp.visible).to be true

      expect(cpp.custom_product_page_versions.count).to eq(1)
      version = cpp.custom_product_page_versions.first
      expect(version.state).to eq("PUBLISHED")
      expect(version.remote_id).to eq("ver_remote_1")

      expect(version.custom_product_page_localizations.count).to eq(1)
      loc = version.custom_product_page_localizations.first
      expect(loc.locale).to eq("en-US")
      expect(loc.remote_id).to eq("loc_remote_1")
    end

    it "deletes stale local CPPs not in API response" do
      stale_cpp = create(:custom_product_page, organization: organization, apple_app: apple_app, remote_id: "stale_cpp")

      empty_page = { "data" => [], "links" => {} }
      allow(service).to receive(:list) do |app_id:, &block|
        block.call(empty_page)
      end

      described_class.perform_now(organization_id: organization.id)

      expect(CustomProductPage.find_by(id: stale_cpp.id)).to be_nil
    end

    it "skips if organization not found" do
      expect(service).not_to receive(:list)

      described_class.perform_now(organization_id: -1)
    end

    it "skips if free plan (entitlement disabled)" do
      user.update!(plan_tier: :free)

      expect(service).not_to receive(:list)

      described_class.perform_now(organization_id: organization.id)
    end

    it "skips if no active credential" do
      credential.update!(active: false)

      expect(service).not_to receive(:list)

      described_class.perform_now(organization_id: organization.id)
    end

    it "continues syncing other apps if one fails" do
      apple_app2 = create(:apple_app, organization: organization, sku: "other_sku")

      call_count = 0
      allow(service).to receive(:list) do |app_id:, &block|
        call_count += 1
        if call_count == 1
          raise StandardError, "API Error"
        else
          block.call({ "data" => [], "links" => {} })
        end
      end

      expect { described_class.perform_now(organization_id: organization.id) }.not_to raise_error
    end

    it "upserts existing CPPs without duplicating" do
      existing = create(:custom_product_page, organization: organization, apple_app: apple_app, remote_id: "cpp_remote_1", name: "Old Name")

      cpp_page = {
        "data" => [
          {
            "id" => "cpp_remote_1",
            "attributes" => { "name" => "Updated Name", "visible" => true }
          }
        ],
        "links" => {}
      }

      allow(service).to receive(:list) do |app_id:, &block|
        block.call(cpp_page)
      end
      allow(service).to receive(:versions).and_return({ "data" => [] })

      described_class.perform_now(organization_id: organization.id)

      expect(organization.custom_product_pages.count).to eq(1)
      existing.reload
      expect(existing.name).to eq("Updated Name")
    end
  end
end
