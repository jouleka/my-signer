require "rails_helper"

RSpec.describe StoreListingTranslationJob do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:app) { create(:apple_app, organization: organization) }
  let(:source) { create(:store_listing, organization: organization, listable: app) }
  let(:target) { create(:store_listing, organization: organization, listable: app, locale: "de-DE", translation_status: "pending") }
  let(:translator) { instance_double(StoreListingSync::AiTranslator) }

  def translate
    described_class.perform_now(organization_id: organization.id, store_listing_id: target.id, base_listing_id: source.id)
  end

  before { allow(StoreListingSync::AiTranslator).to receive(:new).and_return(translator) }

  it "records failures, keeps the draft, refunds quota and permits retry" do
    allow(translator).to receive(:translate!).and_raise("Provider unavailable")
    description = target.description
    expect { translate }.to raise_error("Provider unavailable")
    expect(organization.reload.ai_translations_count).to eq(0)
    expect(target.reload.translation_status).to eq("failed")
    expect(target.metadata["translation_error"]).to eq("Provider unavailable")
    expect(target.description).to eq(description)
  end

  it "clears the pending state if the quota ran out after enqueueing" do
    organization.update!(ai_translations_count: organization.entitlements.max_ai_translations_per_month,
      ai_translations_reset_at: Time.current)
    expect(translator).not_to receive(:translate!)
    expect { translate }.to raise_error(/monthly AI translation limit/)
    expect(target.reload.translation_status).to eq("failed")
  end

  it "does not refund a successful translation when broadcasting fails" do
    allow(translator).to receive(:translate!) { target.update!(description: "Translated", translation_status: "needs_review") }
    allow_any_instance_of(StoreListing).to receive(:trigger_live_refresh).and_raise("Broadcast unavailable")
    expect { translate }.not_to raise_error
    expect(organization.reload.ai_translations_count).to eq(1)
    expect(target.reload.translation_status).to eq("needs_review")
  end

  it "rejects a source belonging to a different app without using quota" do
    source.update!(listable: create(:apple_app, organization: organization, sku: "another-app"))
    expect(translator).not_to receive(:translate!)
    expect { translate }.to raise_error(/invalid source/)
    expect(organization.reload.ai_translations_count).to eq(0)
  end
end
