require "rails_helper"

RSpec.describe PostReviewReplyJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :pro_plan) }
  let(:organization) { create(:organization, owner: user) }
  let(:apple_app) { create(:apple_app, organization: organization) }
  let(:credential) { create(:app_store_connect_credential, organization: organization) }

  describe "Apple reply" do
    let(:review) do
      create(:app_review,
        organization: organization,
        reviewable: apple_app,
        reply_text: "Thanks for your feedback!",
        reply_status: "pending"
      )
    end

    let(:asc_client) { instance_double(AppStoreConnect::Client) }
    let(:asc_reviews) { instance_double(AppStoreConnect::Reviews) }

    before do
      credential
      allow(AppStoreConnect::Client).to receive(:new).and_return(asc_client)
      allow(AppStoreConnect::Reviews).to receive(:new).and_return(asc_reviews)
    end

    it "posts reply and updates status to posted" do
      expect(asc_reviews).to receive(:post_response)
        .with(review_id: review.remote_id, response_body: "Thanks for your feedback!")
        .and_return({ "data" => { "id" => "resp1" } })

      described_class.perform_now(app_review_id: review.id)

      review.reload
      expect(review.reply_status).to eq("posted")
      expect(review.reply_posted_at).to be_present
    end

    it "retries (leaving status pending) on the first transient error instead of permanently failing" do
      # L-13: the first error must re-enqueue via retry_on, NOT mark failed —
      # otherwise the declared retry_on is dead. With the :test adapter retry_on
      # catches and re-enqueues rather than raising.
      allow(asc_reviews).to receive(:post_response).and_raise(StandardError, "API error")

      expect {
        described_class.perform_now(app_review_id: review.id)
      }.to have_enqueued_job(described_class)

      review.reload
      expect(review.reply_status).to eq("pending")
    end

    it "marks reply_status failed only after the final attempt is exhausted" do
      allow(asc_reviews).to receive(:post_response).and_raise(StandardError, "API error")

      # Simulate the final attempt: perform_now increments executions, so
      # pre-setting it to MAX_ATTEMPTS - 1 lands at MAX_ATTEMPTS inside perform,
      # where the job stops retrying and marks the review failed.
      job = described_class.new(app_review_id: review.id)
      job.executions = described_class::MAX_ATTEMPTS - 1

      expect {
        job.perform_now
      }.not_to have_enqueued_job(described_class)

      review.reload
      expect(review.reply_status).to eq("failed")
    end
  end

  describe "Android reply" do
    let(:android_app) { create(:android_app, organization: organization) }
    let(:gp_credential) do
      create(:google_play_credential, organization: organization,
        service_account_json: '{"type":"service_account","project_id":"test","private_key":"fake","client_email":"test@test.iam.gserviceaccount.com","client_id":"123"}')
    end

    let(:review) do
      create(:app_review,
        organization: organization,
        reviewable: android_app,
        reply_text: "Thank you!",
        reply_status: "pending"
      )
    end

    let(:gp_client) { instance_double(GooglePlay::Client) }
    let(:gp_reviews) { instance_double(GooglePlay::Reviews) }

    before do
      gp_credential
      allow(GooglePlay::Client).to receive(:new).and_return(gp_client)
      allow(GooglePlay::Reviews).to receive(:new).and_return(gp_reviews)
    end

    it "posts reply and updates status to posted" do
      expect(gp_reviews).to receive(:reply)
        .with(
          package_name: android_app.package_name,
          review_id: review.remote_id,
          reply_text: "Thank you!"
        )
        .and_return(double("reply_result"))

      described_class.perform_now(app_review_id: review.id)

      review.reload
      expect(review.reply_status).to eq("posted")
      expect(review.reply_posted_at).to be_present
    end

    it "retries (leaving status pending) on the first transient error" do
      allow(gp_reviews).to receive(:reply).and_raise(StandardError, "Google API error")

      expect {
        described_class.perform_now(app_review_id: review.id)
      }.to have_enqueued_job(described_class)

      review.reload
      expect(review.reply_status).to eq("pending")
    end

    it "marks failed after the final attempt" do
      allow(gp_reviews).to receive(:reply).and_raise(StandardError, "Google API error")

      job = described_class.new(app_review_id: review.id)
      job.executions = described_class::MAX_ATTEMPTS - 1
      job.perform_now

      review.reload
      expect(review.reply_status).to eq("failed")
    end
  end

  it "skips if review not found" do
    expect {
      described_class.perform_now(app_review_id: -1)
    }.not_to raise_error
  end

  it "skips if reply_text is blank" do
    review = create(:app_review, organization: organization, reviewable: apple_app, reply_text: nil, reply_status: "pending")
    expect {
      described_class.perform_now(app_review_id: review.id)
    }.not_to raise_error
  end

  it "skips if reply_status is not pending" do
    review = create(:app_review, :with_reply, organization: organization, reviewable: apple_app)
    expect {
      described_class.perform_now(app_review_id: review.id)
    }.not_to raise_error
  end
end
