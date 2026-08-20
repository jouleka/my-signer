---
title: ship
description: Build, sign, and upload your app in one command
order: 1
---

# ship

The all-in-one command for building, signing, and uploading your app to TestFlight, App Store, or Google Play.

## Usage

```bash
mysigner ship TARGET [options]
```

## Targets

### iOS Targets

| Target | Description |
|--------|-------------|
| `testflight` | Upload to TestFlight for beta testing |
| `appstore` | Submit to App Store for review |

### Android Targets

| Target | Description |
|--------|-------------|
| `internal` | Upload to Internal Testing track |
| `alpha` | Upload to Closed Testing (Alpha) track |
| `beta` | Upload to Open Testing (Beta) track |
| `production` | Upload to Production track |

---

## iOS Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--scheme` | `-s` | Xcode scheme to build | Auto-detected |
| `--configuration` | `-c` | Build configuration | `Release` |
| `--team` | | Development team ID | From project or API |
| `--bundle-id` | `-b` | Override bundle identifier | From project |
| `--wait` | | Wait for Apple to finish processing the upload (TestFlight build availability or App Store automation polling) | `false` |
| `--no-wait` | | Skip the wait phase. For App Store, this skips the post-upload polling step. | |
| `--release-type` | | App Store release: AFTER_APPROVAL, MANUAL, SCHEDULED | From config |
| `--scheduled-date` | | ISO 8601 date for scheduled release | |
| `--release-notes` | | "What's New" text for the App Store version (iOS `appstore` only) | From release config |
| `--metadata-file` | | Path to a JSON file with App Store submission metadata (iOS `appstore` only) | |
| `--auto-submit` | | Submit for App Store review after upload completes (iOS `appstore` only). Boolean: `--auto-submit` / `--no-auto-submit`. | From dashboard release config (else `true`) |

## Android Options

| Option | Description | Default |
|--------|-------------|---------|
| `--platform android` | Force Android build (optional — auto-detected from target) | Auto-detected |
| `--package-name` | Override package name | From project |
| `--version` | Set version name (e.g., 1.2.0) | From project |
| `--release-notes` | Release notes for Play Store | |
| `--auto-submit` | Submit/promote on the selected track automatically. Boolean: `--auto-submit` / `--no-auto-submit`. | From dashboard CLI defaults |

---

## iOS Examples

### Ship to TestFlight

```bash
# Auto-detect scheme and build
mysigner ship testflight

# Specify scheme
mysigner ship testflight --scheme MyApp

# Wait for Apple to process
mysigner ship testflight --wait
```

### Submit to App Store

```bash
# Build and submit for review
mysigner ship appstore

# With specific release type
mysigner ship appstore --release-type MANUAL

# Schedule release for a specific date
mysigner ship appstore --release-type SCHEDULED --scheduled-date 2026-04-01T10:00:00Z
```

> **Note:** When shipping to App Store, make sure you've configured your release metadata (What's New, etc.) in the MySigner dashboard first.

---

## Android Examples

### Upload to Internal Testing

```bash
# --platform android is optional (auto-detected from target name)
mysigner ship internal --platform android

# These are equivalent
mysigner ship internal
```

### Upload to Beta Track

```bash
mysigner ship beta --platform android --release-notes "Bug fixes and improvements"
```

### Deploy to Production

```bash
mysigner ship production --platform android
```

> **Note:** Google Play requires the first build for each track to be uploaded manually through the Play Console. After that, `mysigner ship` works automatically.
>
> **Tip:** To set the version name, use `mysigner ship TRACK --version 1.2.0`, or update it in your project's `build.gradle`.

---

## Workflow

When you run `mysigner ship`, the CLI performs these steps:

### iOS (TestFlight)
1. **Detect** - Find your project and identify framework (Native, React Native, Flutter, Ionic/Capacitor, Expo)
2. **Pre-build** - Run framework-specific steps if needed (`expo prebuild`, `cap sync`, etc.)
3. **Validate** - Check signing configuration
4. **Build** - Run `xcodebuild` to create an archive
5. **Export** - Export the archive to IPA with App Store signing
6. **Upload** - Upload to App Store Connect

### iOS (App Store)
Same as TestFlight, plus:
7. **Wait** - Poll for build processing completion (every 3 minutes, up to 30 minutes)
8. **Submit** - Create App Store version, apply release configuration, and submit for review

### Android
1. **Detect** - Find your project and identify framework (Native, React Native, Flutter, Ionic/Capacitor, Expo, MAUI)
2. **Pre-build** - Run framework-specific steps if needed (`cap sync android`, `flutter pub get`, etc.)
3. **Fetch Keystore** - Get signing credentials from MySigner
4. **Increment Version** - Auto-increment version code if needed
5. **Build** - Run Gradle to create signed AAB
6. **Upload** - Upload to Google Play

---

## Time Estimates

| Target | Estimated Time |
|--------|---------------|
| TestFlight | 3-7 minutes |
| App Store | 15-30 minutes (includes processing wait) |
| Android tracks | 3-10 minutes |

---

## Example Output

```bash
$ mysigner ship testflight

🚀 My Signer - Ship to TestFlight
================================================================================

This will:
  1️⃣  Detect and build your project
  2️⃣  Export IPA for App Store
  3️⃣  Upload to TestFlight

⏱️  Estimated time: 3-7 minutes

================================================================================
[1/3] Building Archive
================================================================================

✓ Found: MyApp.xcworkspace (Native iOS)

🎯 Target: MyApp
📦 Bundle ID: com.company.myapp
⏱️  Estimated: 2-5 minutes

🔍 Validating signing setup...
✓ Signing configuration valid

Building archive...

✓ Build complete in 2m 34s

================================================================================
[2/3] Exporting IPA
================================================================================

⏱️  Estimated: 30-90 seconds

✓ Export complete in 45s
📦 IPA: ~/Archives/MyApp.ipa

================================================================================
[3/3] Uploading to TestFlight
================================================================================

⏱️  Estimated: 1-3 minutes

🔐 Fetching App Store Connect credentials...
✓ Credentials loaded

Uploading to App Store Connect...
▸ Validating IPA
▸ Uploading... 45.2 MB / 45.2 MB (100%)
▸ Upload complete

================================================================================
🎉 SUCCESS! Your app is on TestFlight!
================================================================================

📊 Summary

  Project:     MyApp
  Bundle ID:   com.company.myapp
  Target:      MyApp
  IPA Size:    45.2 MB

⏱️  Time Breakdown

  Build:       2m 34s
  Export:      45s
  Upload:      1m 12s
  ------------------------------
  Total:       4m 31s

📁 Files Created

  Archive:     /path/to/MyApp.xcarchive
  IPA:         /path/to/MyApp.ipa

🔮 Next Steps

  1. Wait 5-15 minutes for Apple to process your build
  2. Open App Store Connect:
     https://appstoreconnect.apple.com/apps
  3. Add testers and distribute via TestFlight
```

---

## Command Aliases

| Alias | Command |
|-------|---------|
| `s` | `ship` |

```bash
# These are equivalent
mysigner s testflight
mysigner ship testflight
```

---

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error |

---

## Troubleshooting

### "App Store Connect credentials not configured"

```bash
Quick fix:
  mysigner doctor    # Auto-configure now

Or manually:
  1. Run: mysigner onboard
  2. Follow Step 5 to add credentials
```

### "No signing identity for team"

Your Mac doesn't have the signing certificate installed.

**Fix:**
1. Open Xcode → Settings → Accounts
2. Select your team → Download Manual Profiles
3. Or run `mysigner doctor` for guidance

### "Bundle ID not registered"

The bundle ID in your project isn't registered in App Store Connect.

**Fix:**
```bash
mysigner bundleid register com.company.myapp
mysigner sync ios
```

### Build Failed

Check the error output and run:
```bash
mysigner doctor
```

---

## Related Commands

- [`build`](build) - Build without uploading
- [`submit`](submit) - Submit for review without building
- [`doctor`](doctor) - Diagnose build issues
- [`android`](android) - Android-specific commands
