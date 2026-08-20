---
title: iOS to TestFlight
description: Build and deploy your iOS app to TestFlight for beta testing
order: 2
---

# iOS to TestFlight

This guide walks you through building and deploying your iOS app to TestFlight for beta testing.

---

## Prerequisites

Before you begin, ensure you have:

- **macOS** with Xcode 14+ installed
- **Apple Developer Program** membership (Admin or App Manager role)
- **Mobile project** that builds to iOS (native Swift/Objective-C, React Native, Flutter, Ionic/Capacitor, or Expo)
- **MySigner account** with App Store Connect credentials configured

> **Don't have credentials set up?** Follow the [Getting Started](/docs/quickstart/getting-started) guide first.

---

## Step 1: Verify Your Setup

Run the doctor command to check your configuration:

```bash
mysigner doctor
```

The doctor will verify:

- ✓ CLI authentication
- ✓ App Store Connect credentials
- ✓ Xcode and build tools
- ✓ Project configuration
- ✓ Signing identity and provisioning profiles

If there are issues, the doctor will offer to fix them automatically.

---

## Step 2: Configure TestFlight Beta Groups (Optional)

If you want specific testers to receive builds automatically:

1. Go to the MySigner dashboard
2. Navigate to your iOS app
3. Under **TestFlight**, configure beta groups
4. Add tester emails or sync from App Store Connect

> **Tip:** You can also manage testers directly in App Store Connect after the build is uploaded.

---

## Step 3: Ship to TestFlight

From your project's root directory, run:

```bash
mysigner ship testflight
```

This single command:

1. **Detects** your project type (Native, React Native, Flutter, etc.)
2. **Validates** signing configuration
3. **Builds** the app using `xcodebuild`
4. **Exports** an IPA with App Store distribution signing
5. **Uploads** to App Store Connect (build appears in TestFlight after Apple processes it)

### With Options

```bash
# Specify a scheme (useful for multi-scheme projects)
mysigner ship testflight --scheme MyApp

# Use a specific build configuration
mysigner ship testflight --configuration Release

# Wait for Apple to finish processing
mysigner ship testflight --wait
```

---

## Step 4: Monitor Progress

The CLI shows real-time progress:

```
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

Uploading to App Store Connect...
▸ Validating IPA
▸ Uploading... 45.2 MB / 45.2 MB (100%)
▸ Upload complete

================================================================================
🎉 SUCCESS! Your app is on TestFlight!
================================================================================
```

---

## Step 5: Wait for Processing

After upload, Apple processes your build:

| Phase | Duration |
|-------|----------|
| Upload validation | 1-2 minutes |
| Build processing | 5-15 minutes |
| TestFlight available | Immediately after processing |

You can add `--wait` to have the CLI notify you when processing is done:

```bash
mysigner ship testflight --wait
```

```
⏳ Waiting for App Store Connect to process the build...
This may take 5-15 minutes...
```

> **Tip:** For fully automated processing + submission, use `mysigner ship appstore` instead — it polls every 3 minutes until the build is processed and then auto-submits for review.

---

## Step 6: Distribute to Testers

Once processing completes:

1. **Automatic distribution**: If you configured beta groups in MySigner, testers receive notifications immediately

2. **Manual distribution**: 
   - Open [App Store Connect](https://appstoreconnect.apple.com/)
   - Navigate to your app → TestFlight
   - Select the build and add testers/groups

---

## Workflow Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Build     │────▶│   Export    │────▶│   Upload    │
│  Archive    │     │    IPA      │     │  to ASC     │
└─────────────┘     └─────────────┘     └─────────────┘
                                               │
                                               ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Testers   │◀────│  TestFlight │◀────│  Processing │
│   Notified  │     │   Ready     │     │   Complete  │
└─────────────┘     └─────────────┘     └─────────────┘
```

---

## Time Estimate

| Step | Duration |
|------|----------|
| Build | 2-5 minutes |
| Export | 30-90 seconds |
| Upload | 1-3 minutes |
| Processing | 5-15 minutes |
| **Total** | **10-25 minutes** |

---

## Common Issues

### "No signing identity found"

Your Mac doesn't have the distribution certificate.

**Fix:**
```bash
mysigner doctor
```

Or manually:
1. Open Xcode → Settings → Accounts
2. Select your team
3. Click "Download Manual Profiles"

### "Profile doesn't include signing certificate"

The provisioning profile was created with a different certificate.

**Fix:**
```bash
mysigner doctor
```

Doctor can detect the mismatch and auto-create a new profile with your current certificate. Alternatively, refresh your data first and then let doctor fix it:

```bash
mysigner sync --force
mysigner doctor
```

### "Bundle ID not registered"

Your app's bundle ID isn't in App Store Connect.

**Fix:**
```bash
# Register the bundle ID
mysigner bundleid register com.company.myapp

# Sync to refresh
mysigner sync
```

### Build takes too long

For large projects:

1. **Use derived data caching** in CI/CD
2. **Clean only when needed**: `xcodebuild clean` resets all caches
3. **Disable bitcode** if not required (deprecated in Xcode 14+)

---

## Next Steps

- [Submit to App Store](/docs/guides/ios-appstore) - Submit for App Store review
- [GitHub Actions CI/CD](/docs/guides/ci-cd-github) - Automate TestFlight deployments
- [Troubleshooting](/docs/guides/troubleshooting) - More issue solutions

---

## Related Commands

- [`ship`](/docs/commands/ship) - Full ship command reference
- [`build`](/docs/commands/build) - Build without uploading
- [`doctor`](/docs/commands/doctor) - Diagnose issues
- [`profiles`](/docs/commands/profiles) - Manage provisioning profiles

## Related Dashboard Pages

- [Releases](/docs/dashboard/releases) - Manage release notes (with optional review workflow), release checklists, and locale-specific listings
- [Screenshot Studio](/docs/dashboard/screenshot-studio) - Generate the screenshots required for TestFlight beta groups
- [Reviews & Ratings](/docs/dashboard/reviews) - Monitor App Store reviews after the build is approved
- [Analytics](/docs/dashboard/analytics) - Track install / retention / stability metrics post-release
