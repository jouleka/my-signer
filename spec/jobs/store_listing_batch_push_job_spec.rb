require "rails_helper"

RSpec.describe StoreListingBatchPushJob do
  it "records a failed locale and continues with the remaining locale in the batch" do
    organization = create(:organization)
    app = create(:apple_app, organization: organization)
    english = create(:store_listing, organization: organization, listable: app, locale: "en-US", push_status: "pushing")
    german = create(:store_listing, organization: organization, listable: app, locale: "de-DE", push_status: "pushing")
    first = instance_double(StoreListingSync::ApplePusher)
    second = instance_double(StoreListingSync::ApplePusher)
    allow(StoreListingSync::ApplePusher).to receive(:new).and_return(first, second)
    expect(first).to receive(:push!).ordered.and_raise("English rejected")
    expect(second).to receive(:push!).ordered do
      expect(english.reload.push_status).to eq("failed")
      german.update!(push_status: "success")
    end
    described_class.perform_now(organization_id: organization.id, store_listing_ids: [ english.id, german.id ])
    expect(english.reload.push_error).to eq("English rejected")
    expect(german.reload.push_status).to eq("success")
  end

  it "marks listings left in pushing as failed when the batch dies mid-run" do
    organization = create(:organization)
    app = create(:apple_app, organization: organization)
    english = create(:store_listing, organization: organization, listable: app, locale: "en-US", push_status: "pushing")
    german = create(:store_listing, organization: organization, listable: app, locale: "de-DE", push_status: "pushing")
    allow(StoreListingPushJob).to receive(:perform_now).and_raise(SignalException, "TERM")

    expect do
      described_class.perform_now(organization_id: organization.id, store_listing_ids: [ english.id, german.id ])
    end.to raise_error(SignalException)

    [ english, german ].each do |listing|
      expect(listing.reload.push_status).to eq("failed")
      expect(listing.push_error).to eq(StoreListing::PUSH_INTERRUPTED_MESSAGE)
    end
  end

  it "keeps queued locales fresh while earlier locales are pushed" do
    organization = create(:organization)
    app = create(:apple_app, organization: organization)
    english = create(:store_listing, organization: organization, listable: app, locale: "en-US", push_status: "pushing")
    german = create(:store_listing, organization: organization, listable: app, locale: "de-DE", push_status: "pushing")
    StoreListing.where(id: [ english.id, german.id ]).update_all(updated_at: 14.minutes.ago)
    allow(StoreListingPushJob).to receive(:perform_now) do |store_listing_id:, **|
      expect(german.reload).to be_push_in_progress
      expect(german.updated_at).to be > 1.minute.ago
      StoreListing.find(store_listing_id).update!(push_status: "success")
    end

    described_class.perform_now(organization_id: organization.id, store_listing_ids: [ english.id, german.id ])
    expect([ english.reload.push_status, german.reload.push_status ]).to all(eq("success"))
  end

  it "does not clobber a newer push that started after this run went stale" do
    organization = create(:organization)
    app = create(:apple_app, organization: organization)
    listing = create(:store_listing, organization: organization, listable: app, push_status: "pushing")
    allow(StoreListingPushJob).to receive(:perform_now) do
      # This run hangs past the stale window; a user then starts a new push.
      travel 20.minutes
      StoreListing.where(id: listing.id).mark_pushing!
    end

    described_class.perform_now(organization_id: organization.id, store_listing_ids: [ listing.id ])
    expect(listing.reload.push_status).to eq("pushing")
  ensure
    travel_back
  end
end
