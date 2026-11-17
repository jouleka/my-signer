require "rails_helper"

RSpec.describe StoreListing, "push staleness" do
  let(:organization) { create(:organization) }
  let(:app) { create(:apple_app, organization: organization) }
  let!(:fresh) { create(:store_listing, organization: organization, listable: app, locale: "en-US", push_status: "pushing") }
  let!(:stale) { create(:store_listing, organization: organization, listable: app, locale: "de-DE", push_status: "pushing") }

  before { stale.update_columns(updated_at: 16.minutes.ago) }

  it "treats a pushing listing older than 15 minutes as no longer in progress" do
    expect(described_class.push_in_progress).to contain_exactly(fresh)
    expect(described_class.push_stale).to contain_exactly(stale)
    expect(fresh).to be_push_in_progress
    expect(stale.reload).to be_push_stale
    expect(stale).not_to be_push_in_progress
  end

  it "restarts the staleness clock when listings are marked as pushing" do
    described_class.where(id: stale.id).mark_pushing!
    expect(stale.reload).to be_push_in_progress
    expect(stale.push_error).to be_nil
  end

  it "reports a stale push as failed so the UI stops polling" do
    stale.update_columns(push_status: "pushing", updated_at: 16.minutes.ago)
    fresh.update_columns(push_status: "success")
    status = StoreListingSync::PushStatus.for(app)
    expect(status[:push_status]).to eq("failed")
    expect(status[:push_error]).to include("de-DE: #{StoreListing::PUSH_INTERRUPTED_MESSAGE}")
  end
end
