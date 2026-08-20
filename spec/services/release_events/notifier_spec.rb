require "rails_helper"

RSpec.describe ReleaseEvents::Notifier, type: :service do
  let(:owner) { create(:user, :team_plan) }
  let(:organization) { create(:organization, owner: owner) }

  describe ".notify_ios_state_change" do
    let(:apple_app) do
      create(:apple_app, organization: organization, name: "My iOS App", bundle_id: "com.example.ios")
    end
    let(:version) do
      create(:app_store_version,
             apple_app: apple_app,
             organization: organization,
             version_string: "1.2.3",
             app_store_state: "PREPARE_FOR_SUBMISSION")
    end

    context "when transitioning to a significant state" do
      it "creates a notification for the organization owner" do
        expect {
          version.update!(app_store_state: "READY_FOR_SALE")
        }.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.user).to eq(owner)
        expect(notification.organization).to eq(organization)
        expect(notification.notification_type).to eq("ios_state_change:READY_FOR_SALE")
        expect(notification.title).to eq("Release Live on App Store")
        expect(notification.message).to include("My iOS App")
        expect(notification.message).to include("1.2.3")
        expect(notification.resource).to eq(version)
      end

      it "creates a notification for REJECTED transitions" do
        expect {
          version.update!(app_store_state: "REJECTED")
        }.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.notification_type).to eq("ios_state_change:REJECTED")
        expect(notification.title).to eq("App Store Submission Rejected")
      end

      it "creates a notification for METADATA_REJECTED transitions" do
        expect {
          version.update!(app_store_state: "METADATA_REJECTED")
        }.to change(Notification, :count).by(1)

        expect(Notification.last.notification_type).to eq("ios_state_change:METADATA_REJECTED")
      end

      it "creates a notification for DEVELOPER_REJECTED transitions" do
        expect {
          version.update!(app_store_state: "DEVELOPER_REJECTED")
        }.to change(Notification, :count).by(1)
      end

      it "creates a notification for IN_REVIEW transitions" do
        expect {
          version.update!(app_store_state: "IN_REVIEW")
        }.to change(Notification, :count).by(1)
      end

      it "creates a notification for WAITING_FOR_REVIEW transitions" do
        expect {
          version.update!(app_store_state: "WAITING_FOR_REVIEW")
        }.to change(Notification, :count).by(1)
      end

      it "creates a notification for INVALID_BINARY transitions" do
        expect {
          version.update!(app_store_state: "INVALID_BINARY")
        }.to change(Notification, :count).by(1)
      end

      it "creates a notification for PENDING_DEVELOPER_RELEASE transitions" do
        expect {
          version.update!(app_store_state: "PENDING_DEVELOPER_RELEASE")
        }.to change(Notification, :count).by(1)
      end

      it "uses bundle_id as fallback when app name is blank" do
        apple_app.update_column(:name, "")
        version.reload

        version.update!(app_store_state: "READY_FOR_SALE")

        expect(Notification.last.message).to include("com.example.ios")
      end
    end

    context "when transitioning to an insignificant state" do
      it "does not create a notification for PREPARE_FOR_SUBMISSION" do
        version.update!(app_store_state: "IN_REVIEW")
        Notification.delete_all

        expect {
          version.update!(app_store_state: "PREPARE_FOR_SUBMISSION")
        }.not_to change(Notification, :count)
      end

      it "does not create a notification for PROCESSING_FOR_APP_STORE" do
        expect {
          version.update!(app_store_state: "PROCESSING_FOR_APP_STORE")
        }.not_to change(Notification, :count)
      end
    end

    context "when state does not change" do
      it "does not create a notification on a no-op update" do
        version.update!(app_store_state: "READY_FOR_SALE")
        Notification.delete_all

        expect {
          version.update!(version_string: "1.2.4")
        }.not_to change(Notification, :count)
      end
    end

    context "with multiple organization members" do
      let!(:admin_user) { create(:user) }
      let!(:developer_user) { create(:user) }
      let!(:viewer_user) { create(:user) }

      before do
        create(:membership, user: admin_user, organization: organization, role: :admin)
        create(:membership, user: developer_user, organization: organization, role: :developer)
        create(:membership, user: viewer_user, organization: organization, role: :viewer)
      end

      it "notifies owner, admin, and developer (not viewer)" do
        expect {
          version.update!(app_store_state: "READY_FOR_SALE")
        }.to change(Notification, :count).by(3)

        notified_users = Notification.last(3).map(&:user)
        expect(notified_users).to include(owner, admin_user, developer_user)
        expect(notified_users).not_to include(viewer_user)
      end

      it "does not double-notify the owner if they also have an admin membership" do
        # The ensure_owner_membership! callback already adds owner as admin membership.
        expect {
          version.update!(app_store_state: "READY_FOR_SALE")
        }.to change { Notification.where(user: owner).count }.by(1)
      end
    end

    context "when called directly with a non-AppStoreVersion" do
      it "returns without error" do
        expect { described_class.notify_ios_state_change(nil) }.not_to raise_error
        expect { described_class.notify_ios_state_change(Object.new) }.not_to raise_error
      end
    end

    context "when the apple_app is missing" do
      it "handles the missing association gracefully" do
        allow(version).to receive(:apple_app).and_return(nil)
        allow(version).to receive(:saved_change_to_app_store_state?).and_return(true)
        allow(version).to receive(:saved_change_to_app_store_state).and_return([ "PREPARE_FOR_SUBMISSION", "READY_FOR_SALE" ])
        allow(version).to receive(:app_store_state).and_return("READY_FOR_SALE")

        expect {
          described_class.notify_ios_state_change(version)
        }.not_to change(Notification, :count)
      end
    end

    context "when an unexpected error occurs" do
      it "rescues the error and logs it" do
        allow(Notification).to receive(:create!).and_raise(StandardError, "boom")
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:warn)

        expect {
          version.update!(app_store_state: "READY_FOR_SALE")
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).at_least(:once)
      end
    end

    context "deduplication per day" do
      it "does not create a duplicate notification on the same day for the same transition" do
        version.update!(app_store_state: "READY_FOR_SALE")
        initial_count = Notification.count

        # Toggle to a different state and back on the same day.
        version.update!(app_store_state: "PREPARE_FOR_SUBMISSION")
        expect {
          version.update!(app_store_state: "READY_FOR_SALE")
        }.not_to change(Notification, :count).from(initial_count)
      end
    end
  end

  describe ".notify_android_state_change" do
    let(:android_app) do
      create(:android_app, organization: organization, name: "My Android App", package_name: "com.example.android")
    end
    let(:release) do
      create(:play_store_release,
             android_app: android_app,
             version_code: "42",
             status: "draft")
    end

    context "when transitioning to a significant state" do
      it "creates a notification for the organization owner" do
        expect {
          release.update!(status: "live")
        }.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.user).to eq(owner)
        expect(notification.organization).to eq(organization)
        expect(notification.notification_type).to eq("android_state_change:live")
        expect(notification.title).to eq("Release Live on Google Play")
        expect(notification.message).to include("My Android App")
        expect(notification.message).to include("42")
        expect(notification.resource).to eq(release)
      end

      it "creates a notification for rejected transitions" do
        expect {
          release.update!(status: "rejected")
        }.to change(Notification, :count).by(1)

        expect(Notification.last.notification_type).to eq("android_state_change:rejected")
        expect(Notification.last.title).to eq("Google Play Submission Rejected")
      end

      it "creates a notification for submitted transitions" do
        expect {
          release.update!(status: "submitted")
        }.to change(Notification, :count).by(1)

        expect(Notification.last.title).to eq("Submitted for Google Play Review")
      end

      it "uses package_name as fallback when app name is blank" do
        android_app.update_column(:name, "")
        release.reload

        release.update!(status: "live")

        expect(Notification.last.message).to include("com.example.android")
      end
    end

    context "when transitioning to an insignificant state" do
      it "does not create a notification for removed status" do
        expect {
          release.update!(status: "removed")
        }.not_to change(Notification, :count)
      end

      it "does not create a notification when going back to draft" do
        release.update!(status: "submitted")
        Notification.delete_all

        expect {
          release.update!(status: "draft")
        }.not_to change(Notification, :count)
      end
    end

    context "when status does not change" do
      it "does not create a notification on a no-op update" do
        release.update!(status: "live")
        Notification.delete_all

        expect {
          release.update!(track: "production")
        }.not_to change(Notification, :count)
      end
    end

    context "with multiple organization members" do
      let!(:admin_user) { create(:user) }
      let!(:developer_user) { create(:user) }
      let!(:viewer_user) { create(:user) }

      before do
        create(:membership, user: admin_user, organization: organization, role: :admin)
        create(:membership, user: developer_user, organization: organization, role: :developer)
        create(:membership, user: viewer_user, organization: organization, role: :viewer)
      end

      it "notifies owner, admin, and developer (not viewer)" do
        expect {
          release.update!(status: "live")
        }.to change(Notification, :count).by(3)

        notified_users = Notification.last(3).map(&:user)
        expect(notified_users).to include(owner, admin_user, developer_user)
        expect(notified_users).not_to include(viewer_user)
      end
    end

    context "when called directly with a non-PlayStoreRelease" do
      it "returns without error" do
        expect { described_class.notify_android_state_change(nil) }.not_to raise_error
        expect { described_class.notify_android_state_change(Object.new) }.not_to raise_error
      end
    end

    context "when the android_app is missing" do
      it "handles the missing association gracefully" do
        allow(release).to receive(:android_app).and_return(nil)
        allow(release).to receive(:saved_change_to_status?).and_return(true)
        allow(release).to receive(:saved_change_to_status).and_return([ "draft", "live" ])
        allow(release).to receive(:status).and_return("live")

        expect {
          described_class.notify_android_state_change(release)
        }.not_to change(Notification, :count)
      end
    end

    context "when an unexpected error occurs" do
      it "rescues the error and logs it" do
        allow(Notification).to receive(:create!).and_raise(StandardError, "boom")
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:warn)

        expect {
          release.update!(status: "live")
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).at_least(:once)
      end
    end
  end

  describe "callback integration" do
    it "fires the iOS notifier from the AppStoreVersion after_update callback" do
      apple_app = create(:apple_app, organization: organization)
      version = create(:app_store_version, apple_app: apple_app, organization: organization)

      expect(ReleaseEvents::Notifier).to receive(:notify_ios_state_change).with(version).and_call_original

      version.update!(app_store_state: "READY_FOR_SALE")
    end

    it "fires the Android notifier from the PlayStoreRelease after_update callback" do
      android_app = create(:android_app, organization: organization)
      release = create(:play_store_release, android_app: android_app)

      expect(ReleaseEvents::Notifier).to receive(:notify_android_state_change).with(release).and_call_original

      release.update!(status: "live")
    end

    it "does not fire notifications on initial create (iOS)" do
      apple_app = create(:apple_app, organization: organization)

      expect {
        create(:app_store_version,
               apple_app: apple_app,
               organization: organization,
               app_store_state: "READY_FOR_SALE")
      }.not_to change(Notification, :count)
    end

    it "does not fire notifications on initial create (Android)" do
      android_app = create(:android_app, organization: organization)

      expect {
        create(:play_store_release, android_app: android_app, status: "live")
      }.not_to change(Notification, :count)
    end
  end

  describe "release_activity preference gating" do
    it "skips users with notify_release_activity disabled" do
      apple_app = create(:apple_app, organization: organization, name: "Gated App", bundle_id: "com.example.gated")
      version = create(:app_store_version,
                       apple_app: apple_app,
                       organization: organization,
                       version_string: "1.0.0",
                       app_store_state: "PREPARE_FOR_SUBMISSION")

      owner.update!(notify_release_activity: false)

      expect {
        version.update!(app_store_state: "READY_FOR_SALE")
      }.not_to change { Notification.where(user_id: owner.id).count }
    end
  end
end
