---
title: Notifications
description: Configure email alerts for certificates, profiles, and more
order: 7
---

# Notifications

MySigner can notify you about important events like expiring certificates and profiles. Configure your notification preferences to stay informed.

---

## Overview

Notifications help you:

- **Avoid surprises** - Know before certificates expire
- **Plan ahead** - Schedule renewals in advance
- **Stay secure** - Keep signing resources up to date

---

## Notification Types

### Certificate Expiry

Get notified before iOS signing certificates expire.

**What you'll receive:**
- Email with certificate name and expiration date
- Link to the certificate in the dashboard
- Days remaining until expiration

### Profile Expiry

Get notified before provisioning profiles expire.

**What you'll receive:**
- Email with profile name and expiration date
- Link to the profile in the dashboard
- Affected bundle ID and profile type

### Keystore Expiry

Get notified before Android keystores expire (if applicable).

**What you'll receive:**
- Email with keystore name and expiration date
- Link to the keystore in the dashboard

> **Note:** Most keystores have very long validity (10+ years), so this notification is less common.

### Sync Failures

Get notified when a scheduled or manual sync with App Store Connect or Google Play fails.

**What you'll receive:**
- Email with platform, organization, and the underlying error category
- Direct link to the affected credential or sync log

### Sync Changes

Get notified when a sync detects new or changed resources (new builds, new profiles, certificate updates, store-listing changes pulled in from ASC/Play).

**What you'll receive:**
- Summary of what changed (e.g., "3 new builds processed", "1 profile expiring soon")
- Link to review the changes in the dashboard

### Revocations

Get notified when a certificate or provisioning profile is revoked — locally or on Apple's end.

**What you'll receive:**
- Email identifying the revoked resource and detected timestamp
- Suggested next steps (re-issue, refresh profiles, rerun `mysigner doctor`)

### Member Activity

Get notified when team members join, leave, or have their role changed.

**What you'll receive:**
- Email summarizing the change (actor, target, role before/after)
- Link to the [Audit Log](/docs/dashboard/audit-log) *(Team plan)* or to the team page on other plans

### API Token Activity

Get notified when API tokens are created or revoked in your organizations. Sent to admins other than the actor.

**What you'll receive:**
- Email identifying the token name, actor, and organization
- Link to the API tokens page

### Billing & Plan Changes

Get notified about plan upgrades, plan downgrades, trial expiration, and payment issues (past due, subscription cancelled).

**What you'll receive:**
- Email explaining the change (e.g., "Plan changed to Team", "Payment past due", "Trial ended")
- Link to the pricing page or billing portal

### Release & Review Activity

Get notified about release events across your organizations:

- App Store / Play Store state changes (submitted, live, rejected)
- Release note review workflow (submitted for review, approved, changes requested)
- Negative app reviews
- Android Vitals anomalies

**What you'll receive:**
- In-app notification (with direct link to the affected release or review)
- (Email delivery for some events — where actionable)

### SSO Activity *(Team plan)*

Get notified when the SAML SSO configuration changes (enabled, updated, disabled) or when a new user is auto-provisioned via SSO. Sent to other admins.

**What you'll receive:**
- Email identifying the actor, event, and organization
- Link to the organization's SSO configuration page

### Security Alerts *(Team plan)*

Reserved for failed-login spikes, API token revocations, and other security-sensitive events. (Some delivery paths are wired; some remain opt-in placeholders — see the Team activity audit log for the full event stream.)

### Weekly Audit Digest *(Team plan)*

Weekly email summarising audit events across your organizations. *(Delivery wiring ships in a follow-up.)*

---

## Configuring Notifications

### Access Notification Settings

1. Click **Settings** in the sidebar
2. Select the **Notifications** tab

### Master Toggle

**Email Notifications Enabled** — turn off **all** email notifications at once. This overrides every per-category toggle below.

### Per-Category Toggles

Each notification type can be enabled or disabled individually:

| Toggle | Default | Notes |
|--------|---------|-------|
| Certificate Expiry | On | |
| Profile Expiry | On | |
| Keystore Expiry | On | |
| Sync Failures | On | Admin-relevant |
| Sync Changes | Off | Off by default — can be chatty |
| Revocations | On | |
| Member Activity | On | |
| API Token Activity | On | |
| Billing Changes | On | Plan transitions, trial expiration, payment issues |
| Release Activity | On | App Store / Play Store state, release notes, reviews, Vitals |
| SSO Activity | On | *Team plan.* Config changes + JIT provisioning |
| Security Alerts | On | *Team plan.* Reserved for future security events |
| Weekly Audit Digest | Off | *Team plan.* Delivery wiring coming soon |

### Set Notification Timing (expiry alerts only)

Choose how many days before expiry to be notified (1–90 days). This timing applies to certificate, profile, and keystore expiry notifications only.

| Setting | Best For |
|---------|----------|
| 7 days | Last-minute reminders |
| 14 days | Standard notice |
| 30 days | Planning ahead (default) |
| 60 days | Enterprise/compliance needs |

---

## Notification Delivery

### Email

Notifications are sent to your registered email address.

**Email contents include:**
- Clear subject line (e.g., "Certificate Expiring Soon")
- Resource details
- Expiration date and days remaining
- Direct link to the dashboard
- Action steps

### Timing

- Notifications are sent once per resource per notification window
- You won't be spammed daily for the same expiring item
- Critical reminders at key intervals if enabled

---

## Best Practices

### For Individuals

1. Enable certificate and profile notifications
2. Set timing to 14-30 days
3. Act promptly when notified

### For Teams

1. Ensure admins have notifications enabled
2. Consider multiple team members receiving alerts
3. Create a shared calendar for renewal dates
4. Document renewal procedures

### For CI/CD

1. Monitor certificate expiry in dashboards
2. Schedule regular `mysigner doctor` runs
3. Add renewal tasks to your sprint planning

---

## Certificate Renewal

When you receive a certificate expiry notification:

### For Distribution Certificates

1. Go to Apple Developer Portal
2. Create a new distribution certificate
3. Download and install in Keychain
4. Export the private key as p12
5. Regenerate affected profiles

### For Development Certificates

1. Xcode can often auto-renew development certs
2. Or create manually in Developer Portal
3. Regenerate development profiles

### After Renewal

1. Sync your organization in MySigner
2. Verify new certificate appears
3. Update any CI/CD systems if needed

---

## Profile Renewal

When you receive a profile expiry notification:

### Regenerate the Profile

1. Go to **iOS** → **Profiles** in MySigner
2. Find the expiring profile
3. Click **Regenerate**
4. Download the new profile

### Or in Apple Developer Portal

1. Go to Certificates, Identifiers & Profiles
2. Find the profile
3. Click Edit → Generate
4. Download

### Update Your Build

1. Re-download profiles: `mysigner profile download ID`
2. Or sync: `mysigner sync`
3. Rebuild your app with the new profile

---

## Keystore Renewal

Android keystores typically have 10+ year validity, but if one is expiring:

> **Warning:** Changing your app's signing key after publishing means users must uninstall and reinstall. Use Play App Signing to avoid this.

1. Create a new keystore for new apps
2. For existing apps, consider Google's key upgrade program
3. Upload new keystore to MySigner

---

## Troubleshooting

### Not receiving notifications

1. **Check spam folder** - Notifications may be filtered
2. **Verify email** - Ensure your email is correct in Settings
3. **Check toggles** - Confirm notifications are enabled
4. **Check timing** - You may not be within the notification window yet

### Too many notifications

1. **Increase timing** - Get fewer, earlier reminders
2. **Disable specific types** - Turn off less critical alerts
3. **Clean up resources** - Remove unused certificates/profiles

### Email address is wrong

1. Go to **Settings**
2. Update your email address
3. Verify the new email if required

---

## Future Enhancements

Planned notification features:

- **Slack integration** - Send notifications to Slack channels
- **Webhook support** - Trigger custom automations
- **Weekly audit digest email** - Scheduled delivery for Team orgs (toggle already available; delivery wiring in progress)
- **Security alert fan-out** - Rate-triggered failed-login and suspicious-activity alerts

---

## Related

- [iOS Resources](/docs/dashboard/ios-resources) - Manage certificates and profiles
- [Android Resources](/docs/dashboard/android-resources) - Manage keystores
- [Doctor Command](/docs/commands/doctor) - Check resource health
