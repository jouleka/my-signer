---
title: android
description: Android app registration, building, and management
order: 15
---

# android

Register and manage Android apps, and build AAB files for Google Play.

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner android init` | Auto-detect and register app from project |
| `mysigner android add PACKAGE` | Manually register an app |
| `mysigner android build` | Build an AAB for first-time upload |
| `mysigner android list` | List registered Android apps |
| `mysigner apps` | List all apps (iOS + Android) |

---

## First-Time Android Setup

Google Play requires the **first build** to be uploaded manually through the Play Console. After that, MySigner can upload automatically.

### Workflow

```bash
# 1. Register your app
mysigner android init

# 2. Build AAB for first upload
mysigner android build

# 3. Upload manually to Play Console (one-time)
#    Play Console → Your App → Internal testing → Create release → Upload AAB

# 4. After that, use ship for all future uploads!
mysigner ship internal --platform android
```

---

## android init

Auto-detect package name from your project and register the app.

### Usage

```bash
mysigner android init
```

### Supported Frameworks

- Native Android (Gradle)
- React Native
- Expo
- Capacitor/Ionic
- Flutter
- .NET MAUI
- Xamarin

### Example

```bash
$ cd my-expo-app
$ mysigner android init

🔍 Detecting project...

✓ Found: Expo (React Native) project

📦 Package: com.company.myapp
📱 Name: My App

🔗 Registering with My Signer...
✓ App registered successfully!

Details:
  ID:      1
  Name:    My App
  Package: com.company.myapp

Next steps:
  1. Create app in Google Play Console
  2. Build AAB: mysigner android build
  3. Upload first build manually in Play Console (one-time requirement)
  4. After that: mysigner ship internal --platform android
```

### For Expo Projects

If using Expo without an `android/` folder, add the package name to `app.json`:

```json
{
  "expo": {
    "android": {
      "package": "com.yourcompany.app"
    }
  }
}
```

---

## android add

Manually register an Android app by package name.

### Usage

```bash
mysigner android add PACKAGE_NAME [options]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `PACKAGE_NAME` | Android package name (e.g., com.company.myapp) | Yes |

### Options

| Option | Description |
|--------|-------------|
| `--name` | Display name for the app |

### Example

```bash
$ mysigner android add com.company.myapp --name "My App"

📦 Registering Android app...

  Package: com.company.myapp
  Name:    My App

✓ App registered successfully!

Details:
  ID:      1
  Name:    My App
  Package: com.company.myapp

Next steps:
  1. Create app in Google Play Console (if not done)
  2. Build AAB: mysigner android build
  3. Upload first build manually in Play Console
  4. Then use: mysigner ship internal --platform android
```

---

## android build

Build an Android App Bundle (AAB) for uploading to Google Play.

### Usage

```bash
mysigner android build
```

### What It Does

1. Detects your project framework
2. Fetches keystore from MySigner (if configured)
3. Auto-increments version code (if needed)
4. Builds a signed release AAB
5. Opens the output folder

### Example

```bash
$ mysigner android build

🔨 Building Android App Bundle (AAB)...

🔧 Framework: React Native
📦 Package: com.company.myapp
🔢 Version: 1.0.0 (5)
🔐 Keystore: Production Key

⏱️ This may take a few minutes...

Building...
▸ Configuring project
▸ Running Gradle bundleRelease
▸ Signing AAB

================================================================================
✓ Build complete!
================================================================================

📦 AAB: android/app/build/outputs/bundle/release/app-release.aab
📊 Size: 15.2 MB

Next step:
  Upload this AAB to Google Play Console → Internal testing → Create release

After uploading, you can use:
  mysigner ship internal --platform android

📂 Opening folder...
```

### Auto Version Code Increment

If your local version code would conflict with a version already on Play Store, MySigner automatically increments it:

```
🔢 Version: 1.0.0 (5 → 6)
   ↳ Auto-incremented (5 already on Play Store)
```

---

## android list

List registered Android apps.

### Usage

```bash
mysigner android list
# or
mysigner apps --platform android
```

### Example

```bash
$ mysigner android list

🤖 Android Apps

  • My App
    Package: com.company.myapp

  • Side Project
    Package: com.company.sideproject

Total: 2 app(s)
```

---

## apps

List all apps from both iOS (App Store Connect) and Android (Google Play).

### Usage

```bash
mysigner apps [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--platform` | Filter: ios, android | Both |
| `--search` / `-q` | Search by name or identifier | |

### Example

```bash
$ mysigner apps

📱 iOS Apps

  • My App
    Bundle ID: com.company.myapp

🤖 Android Apps

  • My App
    Package: com.company.myapp
```

---

## Google Play Setup

Before using MySigner for Android, set up in Play Console:

### 1. Create Developer Account

- Go to [Google Play Console](https://play.google.com/console)
- Pay the one-time $25 registration fee
- Complete account verification

### 2. Create Your App

- My Apps → Create app
- Enter app name and details
- Complete the store listing

### 3. Create Service Account

For MySigner to upload automatically:

1. Go to **Settings → API access**
2. Click **Create new service account**
3. In Google Cloud Console:
   - Create a service account
   - Grant **Service Account User** role
   - Create JSON key → Download
4. Back in Play Console:
   - Click **Done** → Grant access
   - Grant **Release manager** access (the minimum required)

### 4. Upload First Build Manually

Google requires the first build for each track to be uploaded manually:

1. **Internal testing → Create release → Upload AAB**
2. Complete release notes
3. Save and review

After this, `mysigner ship internal` will work!

---

## Troubleshooting

### "No Android Project Found"

```bash
$ mysigner android init
Error: No Android project or Expo config found
```

**Fix:**
- Run from a directory with `android/` folder or `app.json` (Expo)
- For Expo, add `android.package` to `app.json`

### "Track not set up"

When shipping to a track for the first time:
```
Error: Track 'internal' requires manual initial release
```

**Fix:**
1. Build: `mysigner android build`
2. Upload manually in Play Console
3. Then `mysigner ship` will work

### "Version Code Already Exists"

MySigner auto-handles this, but if you see issues:
- Sync to get latest version codes: `mysigner sync android`
- Build again (it will auto-increment)

---

## Related Commands

- [`keystore`](keystore) - Manage Android keystores
- [`ship`](ship) - Build and upload to Play Store
- [`sync`](sync) - Sync data from Google Play
