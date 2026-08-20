---
title: Android to Play Store
description: Build and deploy your Android app to Google Play Store
order: 4
---

# Android to Play Store

This guide walks you through building and deploying your Android app to the Google Play Store.

---

## Prerequisites

Before you begin, ensure you have:

- **Java Development Kit (JDK) 11+** installed
- **Android SDK** installed (`ANDROID_HOME` configured)
- **Mobile project** that builds to Android (native Kotlin/Java, React Native, Flutter, Ionic/Capacitor, Expo, or MAUI)
- **Google Play Developer account** with API access
- **MySigner account** with Google Play credentials configured
- **Keystore** uploaded to MySigner

> **New to MySigner?** Complete the [Getting Started](/docs/quickstart/getting-started) guide first.

---

## Step 1: Set Up Google Play Credentials

### Create a Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the **Google Play Android Developer API**
4. Navigate to **IAM & Admin** → **Service Accounts**
5. Create a new service account
6. Grant the **Service Account User** role
7. Create a JSON key and download it

### Link to Google Play Console

1. Go to [Google Play Console](https://play.google.com/console/)
2. Navigate to **Users and permissions**
3. Click **Invite new users**
4. Enter the service account email (from the JSON key)
5. Grant **Release manager** access (the minimum required — Admin works too but grants more than needed)
6. Click **Invite user**

### Add to MySigner

1. Go to MySigner dashboard → **Google Play**
2. Click **Add Credential**
3. Upload the JSON key file
4. MySigner will verify the connection

---

## Step 2: Upload Your Keystore

Android apps must be signed with a keystore. Upload yours to MySigner:

1. Go to MySigner dashboard → **Keystores**
2. Click **Upload Keystore**
3. Fill in the details:

| Field | Description |
|-------|-------------|
| **Keystore File** | Your `.jks` or `.keystore` file |
| **Keystore Password** | Password for the keystore |
| **Key Alias** | Alias of the signing key |
| **Key Password** | Password for the key (often same as keystore) |

4. Click **Upload**
5. Click **Activate** to set as default

> **Important:** Keep a backup of your keystore! If lost, you cannot update your app on Google Play.

---

## Step 3: Verify Setup

Run the doctor command:

```bash
mysigner doctor
```

Ensure you have:

- ✓ Google Play credentials
- ✓ Active keystore
- ✓ JDK installed
- ✓ Gradle configured

---

## Step 4: Prepare Your App

### First-Time Upload

For new apps, you must upload the first build manually:

1. Build an AAB locally or use MySigner
2. Go to Google Play Console
3. Create a new app
4. Upload the AAB to any track (Internal is recommended)
5. Complete the app listing requirements

After the first upload, MySigner can handle all subsequent releases.

### Version Management

MySigner auto-increments your version code. Ensure your `build.gradle` is set up:

```groovy
android {
    defaultConfig {
        versionCode 1
        versionName "1.0.0"
    }
}
```

---

## Step 5: Ship to Internal Testing

From your project's root directory:

```bash
mysigner ship internal --platform android
```

This command:

1. **Detects** your project and framework (React Native, Flutter, Ionic/Capacitor, Expo, native Kotlin/Java, MAUI)
2. **Pre-builds** if needed (`cap sync android`, `flutter pub get`, `expo prebuild`, etc.)
3. **Fetches** keystore from MySigner
4. **Increments** version code
5. **Builds** a signed AAB
6. **Uploads** to Internal Testing track

### Example Output

```
🤖 My Signer - Ship to Google Play (Internal Testing)
================================================================================

This will:
  1️⃣  Detect and build your Android project
  2️⃣  Sign with your keystore
  3️⃣  Upload to Google Play (internal track)

⏱️  Estimated time: 3-10 minutes

================================================================================
[1/3] Building Android App Bundle (AAB)
================================================================================

✓ Found: Android project (Native Android)

📦 Package: com.company.myapp
🔢 Version: 1.2.0 (41 → 42)
   ↳ Auto-incremented (41 already on Play Store)
⏱️  Estimated: 2-5 minutes

================================================================================
[2/3] Signing with Keystore
================================================================================

🔐 Fetching keystore from My Signer...
✓ Using keystore: Production Key
✓ Keystore ready at: ~/.mysigner/keystores/production.jks

✓ Build complete in 2m 18s
📦 AAB: app/build/outputs/bundle/release/app-release.aab

================================================================================
[3/3] Uploading to Google Play
================================================================================

🔐 Fetching Google Play credentials...
✓ Credentials loaded

Uploading to Internal Testing...
▸ Uploading... 28.4 MB / 28.4 MB (100%)
▸ Processing complete

================================================================================
🎉 SUCCESS! Your app is on Google Play (internal track)!
================================================================================

📊 Summary

  Package:      com.company.myapp
  Version:      1.2.0 (42)
  Track:        internal
  AAB Size:     28.4 MB

⏱️  Time Breakdown

  Build:       2m 18s
  Upload:      45s
  ──────────────────────────────
  Total:       3m 03s

📁 Files Created

  AAB:         app/build/outputs/bundle/release/app-release.aab

🔮 Next Steps

  1. Add internal testers in Google Play Console
  2. Testers will receive the build automatically

  Google Play Console: https://play.google.com/console
```

---

## Step 6: Distribute to Testers

### Internal Testing

- Limited to 100 testers
- Testers must be added by email in Google Play Console
- No review required, available immediately

### Add Internal Testers

1. Go to Google Play Console → **Testing** → **Internal testing**
2. Click **Testers** tab
3. Create or select a list
4. Add email addresses
5. Share the opt-in link with testers

---

## Promotion Tracks

Google Play uses tracks for progressive releases:

```
Internal → Closed (Alpha) → Open (Beta) → Production
```

### Ship to Different Tracks

```bash
# Internal Testing (100 testers max)
mysigner ship internal --platform android

# Closed Testing (Alpha)
mysigner ship alpha --platform android

# Open Testing (Beta)
mysigner ship beta --platform android

# Production
mysigner ship production --platform android
```

### With Release Notes

```bash
mysigner ship beta --platform android --release-notes "Bug fixes and performance improvements"
```

---

## Staged Rollouts

For production releases, Google Play supports staged rollouts to minimize risk. You can manage staged rollouts directly in the Google Play Console:

1. Go to **Google Play Console** → Your app → **Production**
2. Select a release and choose **Staged rollout**
3. Set the initial percentage (e.g., 10%)
4. Gradually increase as you gain confidence

### Staged Rollout Strategy

| Stage | Percentage | Duration | Action |
|-------|------------|----------|--------|
| 1 | 5-10% | 1-2 days | Monitor crash rates |
| 2 | 25% | 1-2 days | Check user feedback |
| 3 | 50% | 1 day | Validate at scale |
| 4 | 100% | - | Full release |

> **Tip:** Monitor your crash-free rate in Google Play Console. If it drops below 99%, consider halting the rollout.

---

## Time Estimates

| Track | Review Time | Availability |
|-------|-------------|--------------|
| Internal | None | Immediate |
| Closed (Alpha) | None | Immediate |
| Open (Beta) | None | Immediate |
| Production | 0-7 days | After review |

> **Note:** New apps and apps flagged for review may take longer. Most updates to production go live within hours.

---

## Workflow Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Build     │────▶│    Sign     │────▶│   Upload    │
│    AAB      │     │   Keystore  │     │  to Track   │
└─────────────┘     └─────────────┘     └─────────────┘
                                               │
        ┌──────────────────────────────────────┤
        │                                      │
        ▼                                      ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Internal   │────▶│   Beta      │────▶│ Production  │
│  Testing    │     │   Testing   │     │   Release   │
└─────────────┘     └─────────────┘     └─────────────┘
```

---

## Common Issues

### "Package name not found"

The package name doesn't match any app in your Google Play Console.

**Fix:**
1. Ensure the app exists in Google Play Console
2. Check the package name in `build.gradle` matches
3. Verify your service account has access to the app

### "Version code already exists"

The version code must be higher than any previously uploaded version.

**Fix:**
```bash
# MySigner auto-increments, but you can also set manually
# In build.gradle, increase versionCode
```

### "APK signature is invalid"

Keystore or signing configuration issue.

**Fix:**
1. Verify keystore credentials in MySigner
2. Check key alias and passwords are correct
3. Re-upload keystore if needed

### "Upload failed - API error"

Google Play API permission issue.

**Fix:**
1. Verify service account email has Release Manager access
2. Check Google Play API is enabled in Cloud Console
3. Re-upload Google Play credentials

### Build fails with Gradle error

**Fix:**
```bash
# Clean and rebuild
cd android && ./gradlew clean

# Run with verbose output
mysigner ship internal --platform android --verbose
```

---

## Best Practices

### Version Naming

Use semantic versioning:

```
1.0.0 - Major.Minor.Patch
```

- **Major**: Breaking changes, major features
- **Minor**: New features, improvements
- **Patch**: Bug fixes

### Release Notes

Write clear, user-friendly release notes:

```markdown
What's New in 1.2.0:

• Faster app loading
• Fixed login issues on some devices  
• New dark mode option
• Bug fixes and stability improvements
```

### Testing Strategy

1. **Internal**: Core team testing
2. **Closed Alpha**: Extended team, power users
3. **Open Beta**: Wider audience, opt-in
4. **Production**: Staged rollout

---

## Next Steps

- [GitHub Actions CI/CD](/docs/guides/ci-cd-github) - Automate Android deployments
- [Keystores Management](/docs/commands/keystore) - Manage signing keys
- [Troubleshooting](/docs/guides/troubleshooting) - More issue solutions

---

## Related Commands

- [`ship`](/docs/commands/ship) - Full ship command reference
- [`keystore`](/docs/commands/keystore) - Keystore management
- [`android`](/docs/commands/android) - Android-specific commands
- [`doctor`](/docs/commands/doctor) - Diagnose issues

## Related Dashboard Pages

- [Releases](/docs/dashboard/releases) - Configure release notes per track, run the AI translate / rewrite workflow, manage the release checklist before submission
- [Screenshot Studio](/docs/dashboard/screenshot-studio) - Generate Play Store screenshots and push them directly to Google Play
- [Reviews & Ratings](/docs/dashboard/reviews) - Reply to Play Store reviews and use response templates
- [Analytics](/docs/dashboard/analytics) - Track installs / ANR rate / crash rate / retention during staged rollouts
