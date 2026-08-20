---
title: submit
description: Submit existing builds for App Store or Play Store review
order: 4
---

# submit

Submit an existing build for App Store or Google Play review without building or uploading. Use this when you've already uploaded a build and want to submit it for review.

## Usage

```bash
# iOS - Submit to App Store
mysigner submit [options]

# Android - Promote to a track
mysigner submit TRACK --platform android [options]
```

## iOS Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--bundle-id` | `-b` | Bundle ID | Auto-detected from project |
| `--build-number` | | Specific build number to submit (passed as a string) | Latest |
| `--version` | | Version string for App Store | From project |
| `--whats-new` | | What's New text | From release config |
| `--support-url` | | Support URL | From release config |
| `--marketing-url` | | Marketing URL (optional) | |
| `--privacy-url` | | Privacy Policy URL (optional) | |
| `--release-type` | | AFTER_APPROVAL, MANUAL, or SCHEDULED | From release config |
| `--scheduled-date` | | ISO 8601 date for scheduled release | |
| `--auto-submit` | | Submit for review after the version is prepared. Boolean: `--auto-submit` / `--no-auto-submit`. | From dashboard release config |

## Android Options

| Option | Description | Default |
|--------|-------------|---------|
| `--platform android` | Use Android platform | |
| `--package-name` | Android package name | Auto-detected |
| `--version-code` | Version code to promote (passed as a string) | Prompted |
| `--release-notes` | Release notes for the track | |
| `--auto-submit` | Promote automatically on the selected track. Boolean: `--auto-submit` / `--no-auto-submit`. | From dashboard CLI defaults |

## Android Tracks

| Track | Description |
|-------|-------------|
| `internal` | Internal testing track |
| `alpha` | Closed testing (Alpha) |
| `beta` | Open testing (Beta) |
| `production` | Production release |

---

## iOS Examples

### Submit Latest Build

```bash
# Auto-detect bundle ID and submit latest build
mysigner submit
```

### Submit Specific Build

```bash
# Submit a specific build number
mysigner submit --build-number 42

# Specify bundle ID manually
mysigner submit --bundle-id com.company.myapp --build-number 42
```

### Submit with Metadata

```bash
# With What's New text
mysigner submit --whats-new "Bug fixes and performance improvements"

# With all metadata
mysigner submit \
  --whats-new "New features!" \
  --support-url "https://support.company.com" \
  --privacy-url "https://company.com/privacy"
```

### Release Types

```bash
# Auto-release after approval (default)
mysigner submit --release-type AFTER_APPROVAL

# Hold for manual release
mysigner submit --release-type MANUAL

# Schedule for specific date
mysigner submit --release-type SCHEDULED --scheduled-date 2026-04-01T10:00:00Z
```

---

## Android Examples

### Promote to Production

```bash
# --platform android is optional (auto-detected from track name)
mysigner submit production --platform android

# These are equivalent
mysigner submit production
```

### Promote to Beta

```bash
mysigner submit beta --version-code 42
```

### With Release Notes

```bash
mysigner submit internal --release-notes "Beta release with new features"
```

---

## Example Output (iOS)

```bash
$ mysigner submit --bundle-id com.company.myapp --build-number 42

📤 Submit for App Store Review
================================================================================

✓ Detected bundle ID from project: com.company.myapp

📱 Bundle ID: com.company.myapp

Finding build #42...
✓ Build found: v1.2.0 (42)

Creating App Store version...
✓ Version 1.2.0 created

Setting release metadata...
✓ What's New configured
✓ Release type: AFTER_APPROVAL

Submitting for review...
✓ Submitted successfully

================================================================================
✓ Submission Complete!
================================================================================

🎉 Your app is submitted for App Store review!

Monitor status:
  https://appstoreconnect.apple.com/apps
```

---

## Example Output (Android)

```bash
$ mysigner submit production --platform android

📤 Promote to Google Play Production
================================================================================

✓ Detected package: com.company.myapp

📦 Package: com.company.myapp
🎯 Target Track: Production

🔐 Fetching Google Play credentials...
✓ Credentials loaded

Enter the version code to promote to production:
Version code: 42

📤 Promoting version 42 to production track...

================================================================================
✓ Successfully promoted to production track!
================================================================================

📦 Package: com.company.myapp
🔢 Version Code: 42
🎯 Track: Production

View in Google Play Console:
  https://play.google.com/console
```

---

## Prerequisites

### iOS
- Build must be uploaded and processed by Apple
- App Store Connect credentials configured
- Release configuration set in MySigner dashboard (optional but recommended)

### Android
- Build must be uploaded to Google Play
- Google Play credentials configured
- App must exist in Google Play Console

---

## Tips

### iOS Release Types

| Type | Behavior |
|------|----------|
| `AFTER_APPROVAL` | App releases automatically when approved |
| `MANUAL` | App waits for you to manually release |
| `SCHEDULED` | App releases at the scheduled date/time |

### Scheduled Releases

When using `--scheduled-date`:
- Must be in ISO 8601 format: `2026-04-01T10:00:00Z`
- Must be at least 1 hour in the future
- Automatically sets release type to `SCHEDULED`

### Build Numbers

If you don't specify `--build-number`:
- iOS: Uses the latest processed build for your bundle ID
- Android: You'll be prompted to enter a version code

---

## Related Commands

- [`ship`](ship) - Build, sign, and upload in one step
- [`upload`](upload) - Upload an existing IPA to TestFlight
- [`release`](release) - Manage App Store release configurations used during submission
- [`tracks`](tracks) - List Google Play tracks and version codes
