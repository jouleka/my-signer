require "rails_helper"

RSpec.describe "Release push locks and review gating", type: :request do
  let(:user) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:release_id) { "apple_app_#{apple_app.id}" }
  let!(:listing) { create(:store_listing, organization: organization, listable: apple_app, locale: "en-US") }

  before do
    sign_in user, scope: :user
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  describe "stale push/sync locks" do
    it "refuses a push while another push is genuinely in progress" do
      listing.update_columns(push_status: "pushing", updated_at: 1.minute.ago)
      expect {
        post push_organization_release_path(organization, release_id)
      }.not_to have_enqueued_job(StoreListingBatchPushJob)
      expect(flash[:alert]).to match(/already in progress/i)
    end

    it "lets a new push recover a listing stuck in pushing for over 15 minutes" do
      listing.update_columns(push_status: "pushing", push_error: nil, updated_at: 20.minutes.ago)
      expect {
        post push_organization_release_path(organization, release_id)
      }.to have_enqueued_job(StoreListingBatchPushJob)
      expect(listing.reload).to be_push_in_progress
    end

    it "lets a sync start when a stale push is left behind" do
      listing.update_columns(push_status: "pushing", updated_at: 20.minutes.ago)
      expect {
        post sync_organization_release_path(organization, release_id)
      }.to have_enqueued_job(StoreListingSyncJob)
    end

    it "does not let a sync stuck in queued block a push for an hour" do
      StoreListingSync::OperationStatus.new(apple_app).start
      travel 16.minutes do
        expect {
          post push_organization_release_path(organization, release_id)
        }.to have_enqueued_job(StoreListingBatchPushJob)
      end
    end

    it "still blocks push while a sync is fresh" do
      StoreListingSync::OperationStatus.new(apple_app).start
      expect {
        post push_organization_release_path(organization, release_id)
      }.not_to have_enqueued_job(StoreListingBatchPushJob)
    end
  end

  describe "review workflow gating" do
    context "when the organization is solo (no review workflow)" do
      it "does not block push on a note left in pending_review" do
        create(:release_note, :pending_review, organization: organization, listable: apple_app, version_string: "1.0.0")
        expect {
          post push_organization_release_path(organization, release_id)
        }.to have_enqueued_job(StoreListingBatchPushJob)
      end

      it "does not block push on a note that was rejected before teammates left" do
        create(:release_note, :review_requested_changes, organization: organization, listable: apple_app, version_string: "1.0.0")
        expect {
          post push_organization_release_path(organization, release_id)
        }.to have_enqueued_job(StoreListingBatchPushJob)
      end

      it "allows editing a note left in pending_review" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app, version_string: "1.0.0")
        patch update_release_note_organization_release_path(organization, release_id, note_id: note.id),
          params: { release_note: { rendered_text: "Edited solo" } }, as: :turbo_stream
        expect(response).to have_http_status(:ok)
        expect(note.reload.rendered_text).to eq("Edited solo")
        expect(response.parsed_body["review_required"]).to be(false)
      end
    end

    context "when the organization has multiple members" do
      before { organization.memberships.create!(user: create(:user), role: :developer) }

      it "blocks push on a rejected note" do
        create(:release_note, :review_requested_changes, organization: organization, listable: apple_app, version_string: "1.0.0")
        expect {
          post push_organization_release_path(organization, release_id)
        }.not_to have_enqueued_job(StoreListingBatchPushJob)
        expect(flash[:alert]).to match(/awaiting approval/i)
      end

      it "blocks editing a note awaiting review" do
        note = create(:release_note, :pending_review, organization: organization, listable: apple_app, version_string: "1.0.0")
        patch update_release_note_organization_release_path(organization, release_id, note_id: note.id),
          params: { release_note: { rendered_text: "Changed after submission" } }, as: :turbo_stream
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
