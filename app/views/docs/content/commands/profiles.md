---
title: profiles
description: List and manage provisioning profiles for code signing
order: 8
---

# profiles

List and manage iOS provisioning profiles.

> **Note:** Most users with **Automatic Signing** don't need these commands. Xcode handles profiles automatically. These commands are for **Manual Signing** workflows.

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner profiles` | List all provisioning profiles |
| `mysigner profile download ID` | Download a profile |
| `mysigner profile delete ID` | Delete a profile |

---

## What Are Provisioning Profiles?

Provisioning profiles are required for signing iOS apps. They link:
- Your **signing certificate** (who you are)
- Your **App ID** (bundle identifier)
- Authorized **devices** (for development/ad-hoc only)

### Profile Types

| Type (as listed in CLI output) | Equivalent `--type` filter value | Use Case |
|---|---|---|
| `IOS_APP_DEVELOPMENT` | `DEVELOPMENT` | Testing on registered devices |
| `IOS_APP_ADHOC` | `AD_HOC` | Distribution to registered devices outside App Store |
| `IOS_APP_STORE` | `APP_STORE` | App Store and TestFlight distribution |
| `IOS_APP_INHOUSE` | `ENTERPRISE` | Enterprise in-house distribution |

> **Heads-up:** The `--type` filter on `mysigner profiles` expects the short form (`DEVELOPMENT`, `AD_HOC`, `APP_STORE`, `ENTERPRISE`), but listings and detail views display the App Store Connect form (`IOS_APP_*`). Filter values are case-insensitive.

---

## profiles

List all provisioning profiles in your organization.

### Usage

```bash
mysigner profiles [options]
```

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--type` | `-t` | Filter by type: DEVELOPMENT, AD_HOC, APP_STORE, ENTERPRISE | All |
| `--status` | `-s` | Filter by status: ACTIVE, EXPIRED, INVALID | All |
| `--search` | `-q` | Search by name or identifier | |
| `--page` | | Page number | 1 |
| `--per-page` | | Profiles per page | 50 |

### Examples

```bash
# List all profiles
mysigner profiles

# Filter by type
mysigner profiles --type APP_STORE
mysigner profiles --type DEVELOPMENT

# Filter by status
mysigner profiles --status EXPIRED

# Search by name
mysigner profiles --search "MyApp"
```

### Example Output

```bash
$ mysigner profiles

📄 Provisioning Profiles

  ✓ MyApp Production AppStore (ID: 1)
    Type: IOS_APP_STORE
    Bundle ID: com.company.myapp
    Status: ACTIVE
    Expires: 2027-01-15

  ✓ MyApp Development (ID: 2)
    Type: IOS_APP_DEVELOPMENT
    Bundle ID: com.company.myapp
    Status: ACTIVE
    Expires: 2027-01-15

  ✗ MyApp Widget (ID: 3)
    Type: IOS_APP_STORE
    Bundle ID: com.company.myapp.widget
    Status: EXPIRED
    Expires: 2025-06-01

Page 1 of 1 (3 total)
```

---

## profile download

Download a provisioning profile file (.mobileprovision).

### Usage

```bash
mysigner profile download ID [options]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `ID` | Profile ID (from `mysigner profiles` list) | Yes |

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--output` | `-o` | Output file path | Profile name.mobileprovision |

### Examples

```bash
# Download profile ID 1
mysigner profile download 1

# Download to specific location
mysigner profile download 1 --output ~/Desktop/MyProfile.mobileprovision
```

### Example Output

```bash
$ mysigner profile download 1

📄 Downloading profile...

Fetching profile content...

✓ Profile downloaded successfully!

Details:
  Name:      MyApp Production AppStore
  Type:      IOS_APP_STORE
  Bundle ID: com.company.myapp
  Status:    ACTIVE
  File:      MyApp_Production_AppStore.mobileprovision

File size: 12847 bytes
```

### Installing Downloaded Profiles

After downloading, install the profile:

```bash
# Option 1: Double-click the file in Finder
open MyApp_Production_AppStore.mobileprovision

# Option 2: Copy to Xcode's profiles directory
cp MyApp_Production_AppStore.mobileprovision ~/Library/MobileDevice/Provisioning\ Profiles/
```

---

## profile delete

Delete a provisioning profile from App Store Connect.

### Usage

```bash
mysigner profile delete ID
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `ID` | Profile ID (from `mysigner profiles` list) | Yes |

### Example

```bash
$ mysigner profile delete 3

📄 Deleting profile...

You are about to delete:
  Name: MyApp Widget
  Type: IOS_APP_STORE
  Bundle ID: com.company.myapp.widget

Are you sure you want to delete this profile? (y/n) y

✓ Profile deleted successfully!
```

---

## Automatic vs Manual Signing

### Automatic Signing (Recommended)

With automatic signing, Xcode manages profiles for you:
- No need to download or install profiles manually
- Xcode creates profiles on-demand
- Works with `mysigner build` and `mysigner ship`

Check your project:
```bash
mysigner build
# If it says "Signing: Automatic", you're good!
```

### Manual Signing

With manual signing, you manage profiles yourself:
1. Create profiles in App Store Connect (or via `mysigner doctor`)
2. Download and install them
3. Configure Xcode to use specific profiles

Use manual signing when:
- You need specific entitlements
- Working with extensions
- Enterprise distribution
- Sharing profiles across a team

---

## Common Issues

### Profile Not Found

```bash
mysigner profile download 123
# Profile not found with ID: 123

# Fix: List available profiles first
mysigner profiles

# Or sync from Apple
mysigner sync ios
```

### Profile Expired

Expired profiles cause signing failures. To fix:

1. Check which profiles are expired:
   ```bash
   mysigner profiles --status EXPIRED
   ```

2. Run doctor to auto-create new ones:
   ```bash
   mysigner doctor
   ```

3. Or delete and recreate manually:
   ```bash
   mysigner profile delete 3
   # Then run doctor or create in App Store Connect
   ```

---

## Related Commands

- [`certificates`](certificates) - Manage signing certificates
- [`devices`](devices) - Manage registered devices
- [`signing`](signing) - Configure code signing
- [`doctor`](doctor) - Auto-create missing profiles
