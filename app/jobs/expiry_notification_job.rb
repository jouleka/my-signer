class ExpiryNotificationJob < ApplicationJob
  queue_as :default

  EXPIRED_GRACE_PERIOD = 7.days

  CRITICAL_DAYS = [ 7, 3, 1 ].freeze

  def perform
    # Drive from the org/resource side instead of users × orgs × 3-resource
    # queries. For each org we scan its expiring certs/profiles/keystores ONCE
    # (using the widest per-user window among its interested members) and then
    # fan the matched resources out to each member, applying that member's own
    # threshold via process_resource. This collapses the old O(users×orgs×3)
    # resource scan to O(orgs×3).
    each_org_with_interested_members do |org, members|
      check_org(org, members)
    end
  end

  private

  # Yields [organization, interested_members] for every org that has at least
  # one email-notification-enabled member, preloading members and their orgs so
  # the loop body issues no per-user/per-membership queries.
  def each_org_with_interested_members
    Organization
      .joins(memberships: :user)
      .where(users: { email_notifications_enabled: true })
      .distinct
      .includes(memberships: :user)
      .find_each do |org|
        members = org.memberships.map(&:user).select(&:email_notifications_enabled?)
        next if members.empty?

        yield org, members
      end
  end

  def check_org(org, members)
    cert_members     = members.select(&:notify_certificate_expiry?)
    profile_members  = members.select(&:notify_profile_expiry?)
    keystore_members = members.select(&:notify_keystore_expiry?)

    check_certificates(org, cert_members) if cert_members.any?
    check_profiles(org, profile_members) if profile_members.any?
    check_keystores(org, keystore_members) if keystore_members.any?
  end

  # Widest lookahead window across the interested members, so a single resource
  # scan covers everyone; each member's own threshold is re-applied per resource.
  def max_days_before(members)
    members.map(&:notification_days_before).max.to_i
  end

  def check_certificates(org, members)
    window = max_days_before(members)
    org.apple_certificates.where("expires_at >= ?", EXPIRED_GRACE_PERIOD.ago)
                          .where("expires_at <= ?", window.days.from_now)
                          .find_each do |cert|
      members.each { |user| process_resource(user, org, cert, user.notification_days_before, CRITICAL_DAYS) }
    end
  end

  def check_profiles(org, members)
    window = max_days_before(members)
    org.apple_provisioning_profiles.where("expires_at >= ?", EXPIRED_GRACE_PERIOD.ago)
                                   .where("expires_at <= ?", window.days.from_now)
                                   .find_each do |profile|
      members.each { |user| process_resource(user, org, profile, user.notification_days_before, CRITICAL_DAYS) }
    end
  end

  def check_keystores(org, members)
    window = max_days_before(members)
    org.android_keystores.active.where("expires_at >= ?", EXPIRED_GRACE_PERIOD.ago)
                                .where("expires_at <= ?", window.days.from_now)
                                .find_each do |keystore|
      members.each { |user| process_resource(user, org, keystore, user.notification_days_before, CRITICAL_DAYS) }
    end
  end

  def process_resource(user, org, resource, days_before, critical_days)
    days_remaining = (resource.expires_at.to_date - Date.current).to_i
    notification_kind = should_notify?(days_remaining, days_before, critical_days, user, resource)

    return unless notification_kind

    case notification_kind
    when :expiry_warning
      send_expiry_warning(user, org, resource, days_remaining)
    when :expired
      send_expired_notice(user, org, resource, days_remaining)
    end
  end

  def send_expiry_warning(user, org, resource, days_remaining)
    notification = find_or_create_notification(user, org, resource, "expiry_warning", days_remaining)
    return unless notification.previously_new_record?

    ExpiryNotificationMailer.expiry_warning(user: user, resource: resource, days_remaining: days_remaining).deliver_later
  rescue ActiveRecord::RecordNotUnique
    # Race condition: another process already created this notification
  end

  def send_expired_notice(user, org, resource, days_remaining)
    notification = find_or_create_notification(user, org, resource, "expired", days_remaining)
    return unless notification.previously_new_record?

    ExpiryNotificationMailer.expired_notice(user: user, resource: resource).deliver_later
  rescue ActiveRecord::RecordNotUnique
    # Race condition
  end

  def find_or_create_notification(user, org, resource, notification_type, days_remaining)
    resource_name = resource.respond_to?(:name) ? resource.name : "Resource"
    resource_type_label = resource.class.name.titleize

    title, message = case notification_type
    when "expiry_warning"
      [
        "#{resource_type_label} Expiring Soon",
        days_remaining == 0 ? "#{resource_type_label} '#{resource_name}' expires today." : "#{resource_type_label} '#{resource_name}' expires in #{days_remaining} days."
      ]
    when "expired"
      [
        "#{resource_type_label} Has Expired",
        "#{resource_type_label} '#{resource_name}' has expired."
      ]
    end

    Notification.find_or_create_by!(
      user: user,
      resource_type: resource.class.name,
      resource_id: resource.id,
      notification_type: notification_type,
      notification_date: Date.current
    ) do |n|
      n.organization = org
      n.title = title
      n.message = message
    end
  end

  def should_notify?(days_remaining, days_before, critical_days, user, resource)
    if days_remaining < 0
      # Already expired — send one "expired" notice if not already sent (ever)
      return false if days_remaining.abs > EXPIRED_GRACE_PERIOD.in_days.to_i
      already_notified = Notification.exists?(
        user: user,
        resource_type: resource.class.name,
        resource_id: resource.id,
        notification_type: "expired"
      )
      return already_notified ? false : :expired
    end

    # Notify on threshold day or "expires today" (day 0)
    return :expiry_warning if days_remaining == days_before
    return :expiry_warning if days_remaining == 0

    # Notify on critical days if within user's window
    return :expiry_warning if critical_days.include?(days_remaining) && days_remaining < days_before

    false
  end
end
