---
title: Android Resources
description: Manage keystores, apps, and release tracks
order: 4
---

# Android Resources

The dashboard provides management of your Android app signing resources, including keystores, apps, and Google Play release tracks.

---

## Overview

Android app signing uses different resources than iOS:

| Resource | Purpose |
|----------|---------|
| **Keystores** | Contains signing keys for APKs and AABs |
| **Apps** | Android apps synced from Google Play Console |
| **Tracks** | Release channels (internal, alpha, beta, production) |

---

## Apps

### Viewing Apps

1. Go to **Android** → **Apps** in the sidebar
2. View all apps synced from Google Play Console
3. Click an app to see details

### App Details

Each app page shows:

- **Package Name** - The app identifier (e.g., `com.example.app`)
- **Title** - App name from Google Play
- **Tracks** - Available release tracks with current versions
- **Builds** - Recent builds uploaded to Google Play

### Syncing Apps

Apps sync automatically when you sync with Google Play. To manually sync:

1. Go to your organization page
2. Click **Sync Android**
3. Wait for completion

---

## Keystores

Keystores contain the cryptographic keys used to sign Android apps.

### Why Keystores Matter

- **Identity** - Proves the app comes from you
- **Updates** - All updates must be signed with the same key
- **Google Play** - Required for all apps on the Play Store
- **Permanent** - You cannot change the key after publishing

> **Warning:** If you lose your keystore, you cannot update your app. You would need to create a new app with a different package name.

### Viewing Keystores

1. Go to **Android** → **Keystores**
2. See all keystores for your organization
3. Check which keystore is active

### Uploading a Keystore

1. Click **Upload Keystore**
2. Select your `.jks` or `.keystore` file
3. Enter the keystore details:
   - **Keystore Password** - Password to open the keystore
   - **Key Alias** - Name of the key inside the keystore
   - **Key Password** - Password for the specific key
4. Give it a descriptive name
5. Click **Upload**

MySigner encrypts and stores your keystore securely.

### Creating a New Keystore

If you don't have a keystore, create one with `keytool`:

```bash
keytool -genkey -v \
  -keystore my-release-key.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias my-app-key
```

You'll be prompted for:
- Keystore password
- Key password
- Name and organization details

### Activating a Keystore

Only one keystore can be active at a time per organization:

1. Find the keystore you want to use
2. Click **Activate**
3. The CLI will use this keystore by default

### Downloading a Keystore

To download your keystore file:

1. Find the keystore
2. Click **Download**
3. Enter your credentials when prompted
4. The `.jks` file downloads

### Deleting a Keystore

> **Warning:** Deleting a keystore is permanent. Make sure you have a backup if you still need it.

1. Find the keystore
2. Click **Delete**
3. Confirm the deletion

---

## Tracks

Release tracks are channels for distributing your app on Google Play.

### Track Types

| Track | Purpose | Visibility |
|-------|---------|------------|
| **Internal** | Quick testing with internal testers | Internal only |
| **Alpha** | Early testing with alpha testers | Closed group |
| **Beta** | Public beta testing | Open or closed |
| **Production** | Public release | Everyone |

### Viewing Tracks

1. Go to **Android** → **Tracks**
2. See all tracks for your apps
3. View current version and rollout percentage

### Track Details

Each track shows:

- **Version Code** - Current build number
- **Version Name** - User-visible version string
- **Status** - Draft, in review, active, halted
- **Rollout** - Percentage of users receiving the update

### Rollout Strategies

For production releases, you can do staged rollouts:

| Percentage | Recommended For |
|------------|-----------------|
| 1-5% | Initial release, catch critical bugs |
| 10-25% | Validate stability |
| 50% | Broader testing |
| 100% | Full release |

**To change rollout percentage:**
1. Manage directly in Google Play Console

---

## Play App Signing

Google recommends using Play App Signing, where Google manages your app signing key:

### How It Works

1. You create an **upload key** (your keystore)
2. Google creates and stores the **app signing key**
3. You sign with upload key, Google re-signs with app signing key

### Benefits

- **Key recovery** - Google can recover your app signing key
- **Security** - Your upload key can be rotated if compromised
- **Optimization** - Google can optimize APKs per device

### MySigner Support

MySigner works with both approaches:

| Setup | What MySigner Needs |
|-------|---------------------|
| Play App Signing | Your upload keystore |
| Classic signing | Your app signing keystore |

---

## CLI Commands

Manage Android resources from the command line:

```bash
# List keystores
mysigner keystore list

# Upload a keystore
mysigner keystore upload release.jks

# Download a keystore by ID
mysigner keystore download ID

# Activate a keystore by ID
mysigner keystore activate ID

# List Android apps
mysigner android list

# Ship to internal track
mysigner ship internal --platform android

# Ship to production
mysigner ship production --platform android
```

See [Keystore Commands](/docs/commands/keystore) and [Android Commands](/docs/commands/android) for full reference.

---

## Syncing with Google Play

### Full Sync

1. Go to your organization page
2. Click **Sync Android**
3. Apps and tracks are refreshed

### What Syncs

- Apps from Google Play Console
- Track information
- Current version details
- In-app products (coming soon)

### Sync Requirements

- Valid Google Play credential with appropriate permissions
- Apps must be linked to the service account in Play Console

---

## Best Practices

### Keystore Security

1. **Backup your keystore** - Store copies in secure locations
2. **Strong passwords** - Use unique, strong passwords for keystore and key
3. **Access control** - Limit who can download keystores (Admin/Owner only)
4. **Play App Signing** - Consider using Google's managed signing

### Release Strategy

1. **Use internal testing** - Quick iterations with your team
2. **Alpha for early adopters** - Get feedback before wide release
3. **Beta for polish** - Catch issues before production
4. **Staged rollouts** - Reduce blast radius of issues

### Credential Management

1. **Service account per environment** - Separate staging and production
2. **Minimal permissions** - Only grant what's needed
3. **Regular rotation** - Rotate service account keys periodically

---

## Troubleshooting

### "Keystore password incorrect"

The password doesn't match what was set when creating the keystore.

**Fix:** Try the correct password. If lost, you may need to create a new keystore (for new apps only).

### "Key alias not found"

The key alias name doesn't match what's in the keystore.

**Fix:** Check the alias name with:
```bash
keytool -list -keystore your-keystore.jks
```

### "Upload failed - APK signed with wrong key"

The uploaded build was signed with a different key than previous versions.

**Fix:** Sign with the correct keystore, or if using Play App Signing, ensure you're using the correct upload key.

### "Track not found"

The specified track doesn't exist for this app.

**Fix:** Use one of: `internal`, `alpha`, `beta`, `production`.

---

## Play Store publishing tools

These dashboard sections cover the Play Store side of a release once your keystores and credentials are in place:

- [Releases](/docs/dashboard/releases) — store listings, release notes (with optional review workflow), AI translate / rewrite, release checklists
- [Screenshot Studio](/docs/dashboard/screenshot-studio) — design Google Play screenshots in the canvas editor and push them straight to Google Play
- [Reviews & Ratings](/docs/dashboard/reviews) *(Pro+ for response templates)* — unified inbox for Play Store reviews
- [Analytics](/docs/dashboard/analytics) — installs, retention, ANR rate, crash rate, and Vitals-style metrics

---

## Related

- [Credentials](/docs/dashboard/credentials) - Set up Google Play credentials
- [Android to Play Store](/docs/guides/android-playstore) - Ship to Google Play
- [Screenshot Studio](/docs/dashboard/screenshot-studio) - Generate Play Store screenshots
- [Keystore Commands](/docs/commands/keystore) - CLI keystore management
