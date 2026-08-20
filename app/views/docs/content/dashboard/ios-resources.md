---
title: iOS Resources
description: Manage certificates, provisioning profiles, devices, and bundle IDs
order: 3
---

# iOS Resources

The dashboard provides full visibility and management of your iOS code signing resources synced from App Store Connect.

---

## Overview

iOS app signing requires several interconnected resources:

| Resource | Purpose |
|----------|---------|
| **Certificates** | Identity for code signing |
| **Bundle IDs** | App identifier with capabilities |
| **Devices** | Registered test devices |
| **Provisioning Profiles** | Ties it all together |

---

## Apps

### Viewing Apps

1. Go to **iOS** → **Apps** in the sidebar
2. View all apps synced from App Store Connect
3. Click an app to see details

### App Details

Each app page shows:

- **App Info** - Name, bundle ID, SKU
- **Version History** - Submitted versions and their status
- **Release Configuration** - Settings for App Store releases
- **TestFlight** - Beta testing configuration

### Syncing Apps

Apps are synced automatically when you sync with App Store Connect. To manually sync:

1. Go to your organization page
2. Click **Sync iOS**
3. Wait for completion

---

## Certificates

Certificates are the digital identities used to sign your apps.

### Certificate Types

| Type | Purpose |
|------|---------|
| **Development** | Sign apps for testing on registered devices |
| **Distribution** | Sign apps for App Store and TestFlight |
| **Apple Push (APNs)** | Enable push notifications |

### Viewing Certificates

1. Go to **iOS** → **Certificates**
2. See all certificates for your team
3. Check expiration dates and status

### Certificate Status

| Status | Meaning |
|--------|---------|
| Valid | Active and usable |
| Expiring | Less than 30 days until expiry |
| Expired | No longer valid |
| Revoked | Manually invalidated |

### Downloading Certificates

1. Find the certificate you need
2. Click **Download**
3. The `.cer` file downloads

> **Note:** You'll also need the private key that was used to generate the certificate signing request (CSR). This is typically in your Keychain.

### Certificate Expiry Notifications

MySigner can notify you before certificates expire:

1. Go to **Settings** → **Notifications**
2. Enable **Certificate Expiry** alerts
3. Set how many days before expiry to notify

---

## Provisioning Profiles

Provisioning profiles authorize your app to run on specific devices or be distributed through the App Store.

### Profile Types

| Type | Use Case |
|------|----------|
| **Development** | Testing on registered devices |
| **Ad Hoc** | Distribution to specific devices without App Store |
| **App Store** | Distribution via App Store and TestFlight |
| **Enterprise** | In-house distribution (requires Enterprise account) |

### Viewing Profiles

1. Go to **iOS** → **Profiles**
2. See all profiles for your team
3. Check status, expiration, and included devices

### Creating a Profile

1. Click **Create Profile**
2. Select the profile type
3. Choose the bundle ID
4. Select the certificate
5. For Development/Ad Hoc: select devices to include
6. Enter a name
7. Click **Create**

### Downloading Profiles

1. Find the profile you need
2. Click **Download**
3. The `.mobileprovision` file downloads

### Regenerating Profiles

When you add new devices, you need to regenerate Development and Ad Hoc profiles:

1. Find the profile
2. Click **Regenerate**
3. The profile is updated with current devices

### Profile Status

| Status | Meaning |
|--------|---------|
| Active | Valid and usable |
| Expired | Past expiration date |
| Invalid | Certificate revoked or bundle ID deleted |

---

## Devices

Registered devices can run Development and Ad Hoc builds.

### Viewing Devices

1. Go to **iOS** → **Devices**
2. See all registered devices
3. Filter by platform (iPhone, iPad, Mac, etc.)

### Registering a Device

1. Click **Register Device** or use the quick action
2. Enter the device name (e.g., "John's iPhone 15")
3. Enter the device UDID
4. Select the platform
5. Click **Register**

### Finding the UDID

Several ways to find a device's UDID:

**Using MySigner CLI:**
```bash
mysigner device detect
```

**Using Finder (macOS):**
1. Connect the device
2. Open Finder and select the device
3. Click the device info until UDID appears
4. Right-click to copy

**Using Xcode:**
1. Open Window → Devices and Simulators
2. Select the device
3. Copy the Identifier

### Exporting Devices

To export all devices as CSV:

1. Go to **iOS** → **Devices**
2. Click **Export CSV**
3. Use this for bulk registration in other tools

### Device Limits

Apple limits the number of devices per account type:

| Account Type | Device Limit |
|--------------|--------------|
| Individual | 100 per device type |
| Organization | 100 per device type |
| Enterprise | Unlimited |

> **Tip:** Devices can be removed, but the slot isn't freed until your annual membership renewal.

---

## Bundle IDs

Bundle IDs are unique identifiers for your apps.

### Viewing Bundle IDs

1. Go to **iOS** → **Bundle IDs**
2. See all registered bundle IDs
3. View capabilities and associated apps

### Bundle ID Details

Each bundle ID page shows:

- **Identifier** - The reverse-domain bundle ID (e.g., `com.example.app`)
- **Name** - Human-readable name
- **Capabilities** - Enabled features (push notifications, app groups, etc.)
- **Associated App** - The App Store Connect app using this bundle ID
- **Provisioning Profiles** - Profiles created for this bundle ID

### Capabilities

Capabilities are features your app can use:

| Capability | Description |
|------------|-------------|
| Push Notifications | Receive remote notifications |
| App Groups | Share data between apps |
| Associated Domains | Universal links and Handoff |
| Sign In with Apple | Apple authentication |
| In-App Purchase | Purchase digital content |
| iCloud | Cloud storage and sync |
| HealthKit | Health data access |
| HomeKit | Smart home integration |

Capabilities are managed in the Apple Developer Portal and synced to MySigner.

### Merchant IDs

For apps using Apple Pay:

1. View the bundle ID
2. See associated Merchant IDs
3. Merchant IDs are created in the Developer Portal

### App Groups

For apps sharing data (main app + widget, for example):

1. View the bundle ID
2. See associated App Groups
3. App Groups enable shared containers

---

## Syncing Resources

Manual sync is always available on every plan, and the dashboard also runs recurring background refreshes (Free daily, Pro every 6h, Team every 3h). You can trigger a manual sync at any time:

### Full Sync

1. Go to your organization page
2. Click **Sync iOS**
3. All resources are refreshed

### What Syncs

- Certificates
- Provisioning Profiles
- Devices
- Bundle IDs with capabilities
- Apps from App Store Connect
- TestFlight groups

### Sync Status

After syncing, you can see:

- **Last Synced** - When the last sync completed
- **Status** - Success or error message
- **Changes** - New or updated resources

---

## CLI Commands

Manage iOS resources from the command line:

```bash
# List certificates
mysigner certificates

# List devices
mysigner devices

# Register a device
mysigner device add "Test iPhone" "00001234-..."

# List profiles
mysigner profiles

# Download a profile by ID
mysigner profile download ID

# List bundle IDs
mysigner bundleid list
```

See [CLI Commands](/docs/commands) for full reference.

---

## Troubleshooting

### Profile shows "Invalid"

The certificate was revoked or the bundle ID was deleted.

**Fix:** Create a new profile with a valid certificate.

### Device not in profile

The device was added after the profile was created.

**Fix:** Regenerate the profile to include new devices.

### Certificate expired

The certificate has passed its expiration date.

**Fix:** Generate a new certificate from Apple Developer Portal.

### Capabilities missing

The bundle ID doesn't have the required capabilities.

**Fix:** Enable capabilities in Apple Developer Portal, then sync.

---

## App Store publishing tools

These dashboard sections cover the App Store side of a release once your signing assets are in place:

- [Releases](/docs/dashboard/releases) — store listings, release notes (with optional review workflow), AI translate / rewrite, release checklists
- [Screenshot Studio](/docs/dashboard/screenshot-studio) — design App Store screenshots in the canvas editor and push them straight to App Store Connect
- [Keywords & ASO](/docs/dashboard/keywords) *(Pro+)* — edit keywords per locale and track ranking positions
- [Reviews & Ratings](/docs/dashboard/reviews) *(Pro+ for response templates)* — unified inbox for App Store reviews
- [Custom Product Pages](/docs/dashboard/custom-product-pages) *(Pro+)* — create iOS CPP variants with their own screenshots and keywords
- [Analytics](/docs/dashboard/analytics) — acquisition, retention, and stability metrics from App Store Connect Analytics

---

## Related

- [Credentials](/docs/dashboard/credentials) - Set up App Store Connect
- [Releases](/docs/dashboard/releases) - Configure App Store releases
- [Screenshot Studio](/docs/dashboard/screenshot-studio) - Generate App Store screenshots
- [iOS to TestFlight](/docs/guides/ios-testflight) - Ship to TestFlight
- [Devices Command](/docs/commands/devices) - CLI device management
