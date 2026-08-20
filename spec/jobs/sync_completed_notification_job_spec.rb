require "rails_helper"

RSpec.describe SyncCompletedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :team_plan, notify_sync_changes: true) }
  let(:organization) { create(:organization, owner: user) }
  let(:changes_summary) { [ "2 new apple certificates", "1 new apple provisioning profile" ] }

  before do
    organization.memberships.find_or_create_by!(user: user) { |m| m.role = :admin }
  end

  describe "#perform" do
    it "creates a notification for org members with preference enabled" do
      expect {
        described_class.perform_now(
          organization_id: organization.id,
          changes_summary: changes_summary
        )
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification.user).to eq(user)
      expect(notification.organization).to eq(organization)
      expect(notification.notification_type).to eq("sync_completed")
      expect(notification.title).to eq("Sync Completed")
      expect(notification.message).to include("2 new apple certificates")
    end

    it "does not send email when fewer than 3 changes" do
      expect {
        perform_enqueued_jobs {
          described_class.perform_now(
            organization_id: organization.id,
            changes_summary: changes_summary
          )
        }
      }.not_to change(ActionMailer::Base.deliveries, :count)
    end

    it "sends email when 3+ changes" do
      big_summary = [ "2 new certs", "1 new profile", "3 new devices" ]

      expect {
        perform_enqueued_jobs {
          described_class.perform_now(
            organization_id: organization.id,
            changes_summary: big_summary
          )
        }
      }.to change(ActionMailer::Base.deliveries, :count).by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to include(user.email)
      expect(mail.subject).to include("Sync completed")
    end

    it "respects the notify_sync_changes preference (default false)" do
      user.update!(notify_sync_changes: false)

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          changes_summary: changes_summary
        )
      }.not_to change(Notification, :count)
    end

    it "deduplicates within 6-hour window" do
      described_class.perform_now(
        organization_id: organization.id,
        changes_summary: changes_summary
      )

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          changes_summary: [ "1 new device" ]
        )
      }.not_to change(Notification, :count)
    end

    it "allows notification after dedup window expires" do
      described_class.perform_now(
        organization_id: organization.id,
        changes_summary: changes_summary
      )

      Notification.last.update_columns(created_at: 7.hours.ago)

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          changes_summary: [ "3 new devices" ]
        )
      }.to change(Notification, :count).by(1)
    end

    it "silently returns when organization is not found" do
      expect {
        described_class.perform_now(
          organization_id: -1,
          changes_summary: changes_summary
        )
      }.not_to change(Notification, :count)
    end

    it "notifies multiple members" do
      member = create(:user, notify_sync_changes: true)
      create(:membership, user: member, organization: organization, role: :developer)

      expect {
        described_class.perform_now(
          organization_id: organization.id,
          changes_summary: changes_summary
        )
      }.to change(Notification, :count).by(2)
    end

    context "with a real cache store (L-15 race backstop)" do
      around do |example|
        original = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        example.run
        Rails.cache = original
      end

      it "claims an atomic dedup slot so a concurrent insert that slips past the exists? check cannot duplicate" do
        # Simulate the race: the Notification.exists? precheck returns false for
        # both concurrent runs (no prior notification yet), but the cache-based
        # claim must let only the first one through.
        allow(Notification).to receive(:exists?).and_return(false)

        expect {
          described_class.perform_now(organization_id: organization.id, changes_summary: changes_summary)
          described_class.perform_now(organization_id: organization.id, changes_summary: changes_summary)
        }.to change(Notification, :count).by(1)
      end

      it "releases the dedup claim when notification creation fails so a retry can re-notify" do
        allow(Notification).to receive(:exists?).and_return(false)
        call_count = 0
        allow(Notification).to receive(:create!).and_wrap_original do |orig, *args, **kwargs|
          call_count += 1
          raise ActiveRecord::RecordInvalid.new(Notification.new) if call_count == 1

          orig.call(*args, **kwargs)
        end

        # First run fails inside create! and releases the claim (re-raises).
        expect {
          described_class.perform_now(organization_id: organization.id, changes_summary: changes_summary)
        }.to raise_error(ActiveRecord::RecordInvalid)

        # Retry succeeds because the claim was released.
        expect {
          described_class.perform_now(organization_id: organization.id, changes_summary: changes_summary)
        }.to change(Notification, :count).by(1)
      end
    end
  end
end
