---
title: gp-credential
description: Manage Google Play API credentials
order: 17
---

# gp-credential

Manage Google Play API credentials for Android app distribution.

## Why Manage Credentials?

Google Play credentials (service account JSON keys) are required to upload and manage Android apps on Google Play. This command lets you:

- View all credentials and their status
- Test if a credential can connect to Google Play
- Activate/deactivate credentials
- Clean up old credentials

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner gp-credential list` | List all credentials |
| `mysigner gp-credential delete ID` | Delete a credential |
| `mysigner gp-credential activate ID` | Set as active credential |
| `mysigner gp-credential test ID` | Test Google Play connection |

---

## gp-credential list

List all Google Play credentials in your organization.

### Usage

```bash
mysigner gp-credential list
```

### Example

```bash
$ mysigner gp-credential list

🔑 Google Play Credentials

  ✓ Production Key (ID: 1)
    Developer Account: dev-123456
    Active: Yes
    Last Synced: 2025-01-15 10:30
    Sync Status: success

  ○ Staging Key (ID: 2)
    Developer Account: dev-789012
    Active: No
    Last Synced: 2025-01-14 08:00
    Sync Status: failed

Total: 2 credential(s)
```

### Empty State

If no credentials are configured:

```bash
$ mysigner gp-credential list

🔑 Google Play Credentials

No Google Play credentials found

Set up credentials with: mysigner onboard
```

---

## gp-credential activate

Set a credential as the active one. Only one credential can be active at a time - the server deactivates all others.

### Usage

```bash
mysigner gp-credential activate ID
```

### Example

```bash
$ mysigner gp-credential activate 2

🔑 Activating credential...
✓ Credential activated!

Staging Key is now the active Google Play credential
```

---

## gp-credential test

Test if a credential can successfully connect to the Google Play Developer API.

### Usage

```bash
mysigner gp-credential test ID
```

### Success

```bash
$ mysigner gp-credential test 1

🔑 Testing credential connection...

✓ Connection successful!

  Google Play API is reachable with this credential
```

### Failure

```bash
$ mysigner gp-credential test 2

🔑 Testing credential connection...

✗ Connection failed

  Error: Invalid service account key

💡 Check that:
   → The service account JSON key is valid
   → The service account has Google Play Console access
   → API access is enabled in Google Play Console
```

---

## gp-credential delete

Delete a credential from MySigner.

### Usage

```bash
mysigner gp-credential delete ID
```

> **Warning:** This cannot be undone.

### Example

```bash
$ mysigner gp-credential delete 2

⚠️  You are about to delete Google Play credential ID: 2

Are you sure? This cannot be undone. (y/n) y

✓ Google Play credential deleted
```

---

## Setting Up Credentials

To add a new Google Play credential, use the onboarding wizard:

```bash
mysigner onboard
```

This walks you through:

1. Creating a Google Cloud service account
2. Granting access in Google Play Console
3. Uploading the JSON key to MySigner

### Google Play Console Setup

1. Go to **Google Play Console → Setup → API access**
2. Link your Google Cloud project
3. Create a service account with these permissions:
   - **Release manager** (to upload builds)
   - **View app information** (to read app data)
4. Download the JSON key
5. Run `mysigner onboard` and provide the key

---

## Troubleshooting

### "Connection failed" on Test

Common causes:

1. **Invalid JSON key** - Re-download from Google Cloud Console
2. **Missing permissions** - Grant access in Google Play Console → API access
3. **API not enabled** - Enable Google Play Developer API in Google Cloud Console
4. **Wrong project** - Ensure the service account belongs to the linked project

### "Sync Status: failed"

The credential exists but failed to sync data from Google Play:

```bash
# Test the connection
mysigner gp-credential test ID

# If test passes, try syncing again
mysigner sync android
```

---

## Related Commands

- [`android`](android) - Register apps and build AAB files
- [`tracks`](tracks) - View Google Play tracks
- [`ship`](ship) - Build and upload to Google Play
- [`sync`](sync) - Sync data from Google Play
