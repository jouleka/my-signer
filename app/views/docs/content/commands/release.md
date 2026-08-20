---
title: release
description: Manage App Store release configurations
order: 14
---

# release

Manage App Store release configurations for iOS app distribution.

## What Are Release Configurations?

Release configurations control how your app is submitted and released on the App Store:

- **Auto-submit** - Automatically submit for review after upload
- **Phased release** - Gradually roll out to users over 7 days
- **Release type** - Manual, after approval, or scheduled
- **What's New** - Release notes shown to users
- **URLs** - Support, marketing, and privacy policy links

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner release list` | List all release configurations |
| `mysigner release show ID` | Show details for a configuration |
| `mysigner release create` | Create a new configuration |
| `mysigner release update ID` | Update an existing configuration |

---

## release list

List all release configurations.

### Usage

```bash
mysigner release list [options]
```

### Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--bundle-id` | `-b` | Filter by bundle identifier |

### Example

```bash
$ mysigner release list

🚀 App Store Releases

  • My App (ID: 1)
    Bundle ID: com.example.app
    Release Type: after_approval
    Auto Submit: Yes
    Phased Release: Yes
    Version: 1.2.0

  • Other App (ID: 2)
    Bundle ID: com.example.app2
    Release Type: manual
    Auto Submit: No
    Phased Release: No
    Version: 2.0.0

Total: 2 release(s)
```

### Filter by Bundle ID

```bash
mysigner release list --bundle-id com.example.app
```

---

## release show

Show full details for a release configuration.

### Usage

```bash
mysigner release show ID
```

### Example

```bash
$ mysigner release show 1

🚀 Release Configuration (ID: 1)

Details:
  App Name:        My App
  Bundle ID:       com.example.app
  Version:         1.2.0
  Release Type:    after_approval
  Auto Submit:     Yes
  Phased Release:  Yes

What's New:
  Bug fixes and performance improvements

URLs:
  Support:    https://support.example.com
  Marketing:  https://example.com
  Privacy:    https://example.com/privacy

Scheduled Date: 2026-04-01T10:00:00Z
```

---

## release create

Create a new release configuration for a bundle ID.

### Usage

```bash
mysigner release create [options]
```

### Options

| Option | Description | Required |
|--------|-------------|----------|
| `--bundle-id-id` | Bundle ID **record** ID (numeric — not the reverse-DNS string). Find it via `mysigner bundleid list`. | Yes |
| `--whats-new` | Release notes / What's New text | No |
| `--support-url` | Support URL | No |
| `--marketing-url` | Marketing URL | No |
| `--privacy-url` | Privacy policy URL | No |
| `--auto-submit` | Auto-submit for review | No |
| `--phased-release` | Enable phased release (7-day rollout) | No |
| `--release-type` | manual, after_approval, or scheduled | No |
| `--scheduled-date` | Scheduled release date (ISO 8601) | No |

### Examples

```bash
# Basic setup with auto-submit and phased release
mysigner release create --bundle-id-id 42 --auto-submit --phased-release

# Full configuration
mysigner release create \
  --bundle-id-id 42 \
  --whats-new "New features and bug fixes" \
  --support-url "https://support.example.com" \
  --privacy-url "https://example.com/privacy" \
  --auto-submit \
  --phased-release \
  --release-type after_approval
```

### Example Output

```bash
$ mysigner release create --bundle-id-id 42 --auto-submit --phased-release

🚀 Creating release configuration...

✓ Release configuration created!

Details:
  ID:             1
  Bundle ID:      com.example.app
  Release Type:   after_approval
  Auto Submit:    Yes
  Phased Release: Yes
```

### Conflict (Already Exists)

Each bundle ID can have only one release configuration. If one already exists:

```bash
$ mysigner release create --bundle-id-id 42

✗ Error: Release configuration already exists for this bundle ID

💡 Use 'mysigner release update ID' to modify it
   Run 'mysigner release list' to find the ID
```

---

## release update

Update an existing release configuration. Only the provided options are changed.

### Usage

```bash
mysigner release update ID [options]
```

### Options

Same options as `release create` (all optional for update).

### Examples

```bash
# Update release notes
mysigner release update 1 --whats-new "Bug fixes and improvements"

# Enable phased release
mysigner release update 1 --phased-release

# Disable auto-submit
mysigner release update 1 --no-auto-submit

# Set up scheduled release
mysigner release update 1 \
  --release-type scheduled \
  --scheduled-date 2026-04-01T10:00:00Z

# Update URLs
mysigner release update 1 \
  --support-url "https://support.example.com" \
  --marketing-url "https://example.com" \
  --privacy-url "https://example.com/privacy"
```

### Example Output

```bash
$ mysigner release update 1 --whats-new "New features" --auto-submit

🚀 Updating release configuration...

✓ Release configuration updated!

Details:
  ID:             1
  Bundle ID:      com.example.app
  Release Type:   after_approval
  Auto Submit:    Yes
  Phased Release: Yes
```

---

## Release Types

| Type | Description |
|------|-------------|
| `manual` | Manually release after approval |
| `after_approval` | Automatically release once Apple approves |
| `scheduled` | Release at a specific date/time (requires `--scheduled-date`) |

> **Heads-up on casing:** `mysigner release create/update` accepts the lowercase forms (`manual`, `after_approval`, `scheduled`), while `mysigner ship` and `mysigner submit` expect the uppercase enum (`MANUAL`, `AFTER_APPROVAL`, `SCHEDULED`). Both forms refer to the same release behavior.

---

## CI/CD Usage

Release configurations are especially useful in CI/CD pipelines:

```bash
# Configure release before building
mysigner release update 1 \
  --whats-new "$(cat RELEASE_NOTES.md)" \
  --auto-submit

# Build and ship
mysigner ship appstore
```

### GitHub Actions Example

```yaml
- name: Configure release
  run: |
    mysigner release update 1 \
      --whats-new "${{ github.event.release.body }}" \
      --auto-submit

- name: Ship to App Store
  run: mysigner ship appstore
```

---

## Troubleshooting

### "Release not found"

Check available release configurations:

```bash
mysigner release list
```

### Finding the Bundle ID Record ID

The `--bundle-id-id` is the numeric ID of the bundle ID record, not the bundle identifier string. Find it with:

```bash
mysigner bundleid list
# Look for the ID number next to your bundle identifier
```

---

## Related Commands

- [`ship`](ship) - Build and upload to App Store
- [`submit`](submit) - Submit existing build for review
- [`bundleid`](bundle-ids) - Manage bundle identifiers
- [`validate`](validate) - Check signing configuration
