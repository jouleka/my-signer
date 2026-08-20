require "rails_helper"

RSpec.describe AppleCertificate, type: :model do
  let(:user) { User.create!(email: "cert@example.com", password: "SecurePass123!", confirmed_at: Time.current) }
  let(:organization) { Organization.create!(name: "Org", owner: user) }

  describe ".expiring_within" do
    it "returns certificates expiring within the provided window including end of day" do
      days = 30
      target_date = days.days.from_now.to_date

      # Expiring at the very end of the target day
      expiry_time = target_date.end_of_day

      cert = AppleCertificate.create!(
        organization: organization,
        expires_at: expiry_time,
        remote_id: "cert_#{Time.now.to_i}"
      )

      results = described_class.expiring_within(days)
      expect(results).to include(cert)
    end

    it "excludes certificates expiring after the window" do
      days = 30
      # Expiring the next day
      expiry_time = (days + 1).days.from_now.beginning_of_day

      cert = AppleCertificate.create!(
        organization: organization,
        expires_at: expiry_time,
        remote_id: "cert_later_#{Time.now.to_i}"
      )

      results = described_class.expiring_within(days)
      expect(results).not_to include(cert)
    end
  end
end
