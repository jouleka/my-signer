---
title: tracks
description: List and view Google Play tracks for Android apps
order: 18
---

# tracks

List and view Google Play tracks (release channels) for your Android apps.

## What Are Tracks?

Google Play uses "tracks" as release channels for your Android app:

| Track | Purpose |
|-------|---------|
| `internal` | Internal testing (up to 100 testers) |
| `alpha` | Closed testing |
| `beta` | Open testing |
| `production` | Public release |

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner tracks PACKAGE_NAME` | List all tracks for an app |
| `mysigner track PACKAGE_NAME TRACK_NAME` | Show details for a specific track |

---

## tracks

List all Google Play tracks for an Android app.

### Usage

```bash
mysigner tracks PACKAGE_NAME [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--sort` | Sort tracks alphabetically |

### Example

```bash
$ mysigner tracks com.example.myapp

🎯 Google Play Tracks for com.example.myapp

  📍 production
    Status: completed
    Version codes: 100, 101
    Release status: completed
    Updated: 2025-01-15 10:30

  📍 beta
    Status: inProgress
    Version codes: 102
    Release status: draft
    Updated: 2025-01-14 08:00

Total: 2 track(s)
```

### Empty State

If no tracks are found, it usually means the app hasn't been uploaded to Google Play yet:

```bash
$ mysigner tracks com.example.newapp

🎯 Google Play Tracks for com.example.newapp

No tracks found

Tracks appear after you upload your app to Google Play Console
and sync with: mysigner sync android
```

---

## track

Show detailed information for a specific track, including releases, version codes, and release notes.

### Usage

```bash
mysigner track PACKAGE_NAME TRACK_NAME
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `PACKAGE_NAME` | Android package name | Yes |
| `TRACK_NAME` | Track name (production, beta, alpha, internal) | Yes |

### Example

```bash
$ mysigner track com.example.myapp production

🎯 Track: production
   Package: com.example.myapp

Details:
  Track Name: production
  Status: completed
  Last Updated: 2025-01-15 10:30

Releases:
  Release 1:
    Status: completed
    Version Codes: 100, 101
    Name: 1.0.0
    Release Notes:
      [en-US] Bug fixes and performance improvements
    Rollout: 50.0%
```

---

## Common Track Names

| Track | Description |
|-------|-------------|
| `production` | Live release visible to all users |
| `beta` | Open testing track |
| `alpha` | Closed testing track |
| `internal` | Internal testing (fastest, limited testers) |

Custom tracks can also exist if created in Google Play Console.

---

## Troubleshooting

### "Android app not found"

The package name isn't registered in MySigner:

```bash
# Check registered apps
mysigner apps --platform android

# Register the app
mysigner android add com.example.myapp
```

### "No tracks found"

Tracks only appear after you've uploaded at least one build to Google Play:

```bash
# Sync to refresh data
mysigner sync android

# Or upload a build
mysigner ship internal --platform android
```

---

## Related Commands

- [`android`](android) - Register apps and build AAB files
- [`ship`](ship) - Build and upload to Google Play
- [`gp-credential`](gp-credential) - Manage Google Play credentials
- [`sync`](sync) - Sync data from Google Play
