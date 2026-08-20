---
title: How to Upload to TestFlight Without Xcode
description: Skip the Xcode Organizer. Upload to TestFlight from the command line in one step using App Store Connect API keys.
order: 1
---

# How to Upload to TestFlight Without Xcode

The short version: with an App Store Connect API key (`.p8` file), `xcodebuild` archives your build and `xcrun altool` uploads it. Two commands. The whole flow runs from the terminal, no Xcode Organizer required.

This guide covers the standard Apple-supported way (with `xcodebuild` and `altool`) and the faster way using a CLI tool that does the whole pipeline in one command.

---

## Why You'd Skip Xcode

The Xcode Organizer flow takes about 5 minutes of clicking per build: open Organizer, find the archive, click Distribute, pick TestFlight, confirm through three screens, upload, then refresh until "Apple is still processing" clears.

The CLI flow takes one command and works in CI. Once it's set up, you don't open Xcode at all for releases.

---

## Prerequisites

You'll need:

- **macOS** with Xcode installed (yes, you still need Xcode installed; you just won't open it for releases).
- **An App Store Connect API key** (`.p8` file). You generate this once and reuse it forever.
- **An archived build** of your app, or a working `xcodebuild` invocation that produces one.

---

## Step 1: Create an App Store Connect API Key

Open [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → **Keys** → click the **+** button under **App Store Connect API**.

Pick a name (e.g., "TestFlight uploads"), and assign the **Developer** role (or **App Manager** if you also want to submit for review from this key). Click **Generate**.

You'll see three pieces of data:

1. **Issuer ID**: UUID at the top of the Keys page. Copy it.
2. **Key ID**: 10-character string like `ABCD1234EF`. Copy it.
3. **The `.p8` file itself**: click **Download** next to the key. You can only download it once. Save it somewhere safe.

> Apple deprecated app-specific-password authentication for the notary service in late 2023 and recommends App Store Connect API keys for App Store uploads going forward. App-specific passwords still technically work for some altool flows but are no longer the recommended path. Use API keys.

For convenience, put the `.p8` somewhere predictable:

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_ABCD1234EF.p8 ~/.appstoreconnect/private_keys/
```

`altool` automatically looks for the file at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, so if you name it correctly it picks the key up on its own.

---

## Step 2: Archive Your Build with `xcodebuild`

If you already have an `.ipa` or `.xcarchive`, skip this step.

Otherwise, from your project root:

```bash
xcodebuild archive \
  -workspace YourApp.xcworkspace \
  -scheme YourScheme \
  -destination 'generic/platform=iOS' \
  -archivePath build/YourApp.xcarchive \
  -allowProvisioningUpdates
```

Then export an IPA from the archive:

```bash
xcodebuild -exportArchive \
  -archivePath build/YourApp.xcarchive \
  -exportPath build/ \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

A minimal `ExportOptions.plist` for TestFlight:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

(Apple removed bitcode support in Xcode 14, so the older `uploadBitcode` key is no-op and you can leave it out.)

You'll have `build/YourApp.ipa` after this step.

---

## Step 3: Upload the IPA with `altool`

The current recommended command is `--upload-package`. The legacy `--upload-app` still works but Xcode 26 has known issues with it in some setups, so prefer `--upload-package`:

```bash
xcrun altool --upload-package build/YourApp.ipa \
  --type ios \
  --apple-id <YOUR_APP_APPLE_ID> \
  --bundle-id com.your.bundle \
  --bundle-version 1 \
  --bundle-short-version-string 1.0 \
  --api-key ABCD1234EF \
  --api-issuer 12345678-1234-1234-1234-123456789012
```

`<YOUR_APP_APPLE_ID>` is the numeric App Store ID from App Store Connect (visible in the URL when viewing your app, e.g. `1234567890`). Bundle-version and bundle-short-version-string should match the values in your IPA's `Info.plist`.

`altool` validates the IPA, uploads it, and returns a delivery UUID on success. Apple then processes the build in the background (typically a few minutes to an hour, sometimes longer).

To check upload status afterward, open App Store Connect → your app → TestFlight → Builds. There's no clean altool-only way to poll processing status; the ASC REST API has a `builds` endpoint that returns processing state if you'd rather poll programmatically.

---

## Step 4 (Optional): Submit for External Testing

When the build finishes processing, you can submit it for external testing automatically. There's no `altool` command for that; you'd need to call the App Store Connect API directly. The simplest path is to set up groups and beta review submission once in the dashboard and let new builds inherit those settings.

---

## Common Errors and Fixes

### `Error: No valid iOS code signing identity found`
You're missing a Distribution certificate in your Keychain. Open Xcode once, sign into your team in Settings → Accounts, and click "Download Manual Profiles" or let automatic signing fetch certs.

### `iOS <version> is not installed. Please download and install the platform from Xcode > Settings > Components.`
You have the iOS SDK but not the platform runtime. In Xcode 26+, platform runtimes are downloaded separately from the SDK. Open Xcode → Settings → Components, find the iOS version your build targets, and click the download icon. Expect a multi-gigabyte download.

### `Bundle ID not found`
The bundle ID in your build doesn't match anything registered in your team's Apple Developer Portal. Register it at [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) first.

### `Asset validation failed`
The most common cause is a missing icon, missing launch screen, or a privacy manifest issue. The error message includes a specific reason; fix that and re-archive.

### `Found no destinations for the scheme 'YourScheme' and action archive`
Your scheme isn't shared. Check `YourApp.xcodeproj/xcshareddata/xcschemes/`. If the scheme file is missing, open Xcode once, go to Product → Scheme → Manage Schemes, and check the "Shared" checkbox for your scheme.

---

## The One-Command Way

Steps 2 through 4 (and most of the troubleshooting above) are what MySigner's CLI handles for you. Once configured, the entire flow is:

```bash
mysigner ship testflight
```

Under the hood, it auto-detects your project (native iOS, React Native, Flutter, Capacitor, Expo), runs the right `xcodebuild` invocations, exports the IPA, uploads via the App Store Connect REST API, polls Apple processing, and notifies you when the build is ready for testers.

The free tier ships to TestFlight unlimited. No card required.

---

## When to Use Which

If you ship rarely and don't mind the manual steps, `xcodebuild` + `altool` directly is the lowest-dependency path; you just run the commands when you need a release.

If you ship a lot and want CI to handle it, wrap those commands in a workflow file and maintain it yourself. Most teams who go this route end up extending the script over months as edge cases pile up.

If you'd rather skip the maintenance, MySigner runs the same pipeline (same Apple APIs underneath) plus a dashboard for reviews, ASO, screenshots, and analytics.

All three paths use the same Apple APIs under the hood. Pick based on how much time you want to spend on release engineering.

---

[Start free → mysigner.dev](https://mysigner.dev/users/sign_up)
