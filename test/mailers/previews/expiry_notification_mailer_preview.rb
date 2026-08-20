# Preview all emails at http://localhost:3000/rails/mailers/expiry_notification_mailer
class ExpiryNotificationMailerPreview < ActionMailer::Preview
  def expiry_warning_certificate
    user = User.first || User.new(email: "test@example.com", name: "Test User")
    resource = AppleCertificate.first || AppleCertificate.new(
      name: "Distribution Certificate",
      expires_at: 10.days.from_now,
      organization: Organization.first || Organization.new(name: "Test Org")
    )

    ExpiryNotificationMailer.expiry_warning(
      user: user,
      resource: resource,
      days_remaining: 10
    )
  end

  def expiry_warning_profile
    user = User.first || User.new(email: "test@example.com", name: "Test User")
    resource = AppleProvisioningProfile.first || AppleProvisioningProfile.new(
      name: "App Store Profile",
      expires_at: 5.days.from_now,
      organization: Organization.first || Organization.new(name: "Test Org")
    )

    ExpiryNotificationMailer.expiry_warning(
      user: user,
      resource: resource,
      days_remaining: 5
    )
  end

  def expiry_warning_keystore
    user = User.first || User.new(email: "test@example.com", name: "Test User")
    resource = AndroidKeystore.first || AndroidKeystore.new(
      name: "Release Keystore",
      expires_at: 20.days.from_now,
      organization: Organization.first || Organization.new(name: "Test Org")
    )

    ExpiryNotificationMailer.expiry_warning(
      user: user,
      resource: resource,
      days_remaining: 20
    )
  end
end
