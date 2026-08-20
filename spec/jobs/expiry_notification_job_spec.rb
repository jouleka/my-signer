require "rails_helper"

RSpec.describe ExpiryNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, email_notifications_enabled: true, notification_days_before: 30) }
  let(:organization) { create(:organization, owner: user) }

  before do
    # Mock Android Keystore Validator
    allow(Android::KeystoreValidator).to receive(:new).and_return(
      double(validate!: double(valid_until: 30.days.from_now, fingerprints: { sha256: "fake_fingerprint" }))
    )

    # Ensure user settings are correct
    user.update!(
      notify_certificate_expiry: true,
      notify_profile_expiry: true,
      notify_keystore_expiry: true
    )
  end

  describe "#perform" do
    context "with expiring Apple Certificate" do
      let!(:expiring_cert) do
        create(:apple_certificate,
          organization: organization,
          name: "Expiring Cert",
          expires_at: 7.days.from_now # Critical day
        )
      end

      let!(:safe_cert) do
        create(:apple_certificate,
          organization: organization,
          name: "Safe Cert",
          expires_at: 60.days.from_now
        )
      end

      it "creates a notification for the expiring certificate" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.user).to eq(user)
        expect(notification.resource).to eq(expiring_cert)
        expect(notification.title).to include("Expiring Soon")
        expect(notification.message).to include("7 days")
      end

      it "sends an email notification" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.to change(ActionMailer::Base.deliveries, :count).by(1)

        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to include(user.email)
        expect(mail.subject).to include("Action Required")
      end

      it "does not notify if user disabled certificate notifications" do
        user.update!(notify_certificate_expiry: false)

        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.not_to change(Notification, :count)
      end
    end

    context "with expiring Provisioning Profile" do
      let!(:expiring_profile) do
        create(:apple_provisioning_profile,
          organization: organization,
          name: "Expiring Profile",
          expires_at: 3.days.from_now # Critical day
        )
      end

      it "creates a notification" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.resource).to eq(expiring_profile)
      end
    end

    context "with expiring Android Keystore" do
      let!(:expiring_keystore) do
        create(:android_keystore,
          organization: organization,
          name: "Expiring Keystore",
          expires_at: 30.days.from_now, # Exact threshold day
          active: true
        )
      end

      it "creates a notification" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.resource).to eq(expiring_keystore)
      end
    end

    context "notification logic" do
      it "notifies on threshold day" do
        create(:apple_certificate, organization: organization, expires_at: Date.current + 30.days)
        expect { described_class.perform_now }.to change(Notification, :count).by(1)
      end

      it "notifies on critical days (7)" do
        create(:apple_certificate, organization: organization, expires_at: 7.days.from_now)
        expect { described_class.perform_now }.to change(Notification, :count).by(1)
      end

      it "notifies on critical day 3" do
        create(:apple_certificate, organization: organization, expires_at: 3.days.from_now)
        expect { described_class.perform_now }.to change(Notification, :count).by(1)
      end

      it "notifies on critical day 1" do
        create(:apple_certificate, organization: organization, expires_at: 1.day.from_now)
        expect { described_class.perform_now }.to change(Notification, :count).by(1)
      end

      it "notifies on day 0 (expires today)" do
        create(:apple_certificate, organization: organization, expires_at: Date.current.end_of_day)
        expect { described_class.perform_now }.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.message).to include("expires today")
      end

      it "does not notify on non-critical days (e.g. 20 days)" do
        create(:apple_certificate, organization: organization, expires_at: 20.days.from_now)
        expect { described_class.perform_now }.not_to change(Notification, :count)
      end
    end

    context "duplicate prevention" do
      let!(:expiring_cert) do
        create(:apple_certificate, organization: organization, name: "Dup Test Cert", expires_at: 7.days.from_now)
      end

      it "does not create duplicate notifications on same day" do
        described_class.perform_now
        expect(Notification.count).to eq(1)

        # Run again on the same day
        expect { described_class.perform_now }.not_to change(Notification, :count)
      end

      it "does not send duplicate emails on same day" do
        perform_enqueued_jobs { described_class.perform_now }
        initial_count = ActionMailer::Base.deliveries.count

        perform_enqueued_jobs { described_class.perform_now }
        expect(ActionMailer::Base.deliveries.count).to eq(initial_count)
      end

      it "sets notification_date to today" do
        described_class.perform_now
        expect(Notification.last.notification_date).to eq(Date.current)
      end
    end

    context "expired resources" do
      let!(:expired_cert) do
        create(:apple_certificate, organization: organization, name: "Expired Cert", expires_at: 2.days.ago)
      end

      it "creates an expired notification for recently expired resources" do
        expect { described_class.perform_now }.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.notification_type).to eq("expired")
        expect(notification.title).to include("Has Expired")
        expect(notification.message).to include("has expired")
      end

      it "sends an expired email" do
        expect {
          perform_enqueued_jobs { described_class.perform_now }
        }.to change(ActionMailer::Base.deliveries, :count).by(1)

        mail = ActionMailer::Base.deliveries.last
        expect(mail.subject).to include("Urgent")
        expect(mail.subject).to include("has expired")
      end

      it "does not send expired notice for resources expired > 7 days" do
        expired_cert.update_columns(expires_at: 8.days.ago)

        expect { described_class.perform_now }.not_to change(Notification, :count)
      end

      it "only sends expired notice once per resource (ever)" do
        described_class.perform_now
        expect(Notification.where(notification_type: "expired").count).to eq(1)

        # Run again — should not create another expired notification
        expect {
          described_class.perform_now
        }.not_to change(Notification.where(notification_type: "expired"), :count)
      end
    end

    context "disabled email notifications" do
      it "does not process users with email_notifications_enabled = false" do
        user.update!(email_notifications_enabled: false)
        create(:apple_certificate, organization: organization, expires_at: 7.days.from_now)

        expect { described_class.perform_now }.not_to change(Notification, :count)
      end
    end
  end
end
