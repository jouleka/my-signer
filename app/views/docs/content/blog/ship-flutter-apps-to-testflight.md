---
title: How to Ship a Flutter App to TestFlight Without Touching Xcode
description: Build, sign, and ship Flutter iOS apps to TestFlight from the command line. Skip Xcode entirely after initial setup.
order: 5
---

# How to Ship a Flutter App to TestFlight Without Touching Xcode

**Quick answer:** Run `flutter build ipa`, then upload the IPA with `xcrun altool` and an App Store Connect API key. Or use a tool that does both steps in one command. Both paths skip the Xcode Organizer.

Flutter's release docs end at "now use Xcode to upload." That's the part most Flutter developers actually dread. This article shows the two ways to skip it.

---

## Prerequisites

You'll need:

- macOS with Xcode installed (Flutter still needs Xcode underneath for iOS, even if you never open the GUI)
- A working Flutter project that builds for iOS (`flutter build ios` succeeds)
- A bundle ID registered in [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list)
- An [App Store Connect API key](https://appstoreconnect.apple.com) (`.p8` file, Issuer ID, Key ID)

If you don't have the API key yet, see [App Store Connect API Key Setup](/docs/blog/app-store-connect-api-key-setup) first.

---

## Path 1: Vanilla Flutter + altool

This is the no-extra-tools route. Three commands, plus an ExportOptions.plist you write once.

### Step 1: Build the IPA

From your Flutter project root:

```bash
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist
```

A minimal `ios/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

After this completes (~3-6 minutes for a real app), the IPA will be at `build/ios/ipa/<YourApp>.ipa`.

### Step 2: Upload to TestFlight

Save your `.p8` to `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, then:

```bash
xcrun altool --upload-app \
  --type ios \
  --file build/ios/ipa/YourApp.ipa \
  --apiKey ABCD1234EF \
  --apiIssuer 12345678-1234-1234-1234-123456789012
```

altool validates the IPA and uploads. Apple then processes the build (5-15 minutes typically), and it shows up in TestFlight when ready.

### Step 3: (Optional) Bump the build number

You'll need a higher build number on every upload. Flutter uses the `+N` suffix in `version: 1.0.0+12` (in `pubspec.yaml`). Bump that before each `flutter build ipa`.

---

## Path 2: One Command via MySigner

If the above looks like three steps too many, MySigner's CLI runs the whole pipeline in one command and handles auto-bumping, polling Apple's processing, and submitting.

### One-time setup

```bash
gem install mysigner
mysigner onboard
```

The wizard asks for your ASC API key (upload the `.p8` once, encrypted at rest with AES-256). It auto-detects Flutter from `pubspec.yaml`, so there's no `Fastfile`-style config.

### Ship

From your Flutter project root:

```bash
mysigner ship testflight
```

What happens:

1. Auto-detects Flutter (reads `pubspec.yaml` + `ios/Runner.xcworkspace`)
2. Runs `flutter build ipa` with the right export options
3. Auto-bumps `CFBundleVersion`
4. Uploads via the App Store Connect REST API
5. Polls Apple's processing every 3 minutes
6. Reports when the build is ready for testers

The whole pipeline typically completes in 5-12 minutes (build is the slow part, not the upload).

Free tier ships to TestFlight unlimited, no card.

---

## Common Flutter Shipping Errors

### `Error (Xcode): No profiles for 'com.example.app' were found`

Your bundle ID isn't registered or your team doesn't have a matching provisioning profile. Open Xcode once, sign into your team in Settings → Accounts, and let automatic signing fetch profiles. After that, you can go back to CLI-only.

### `Could not build the application for the simulator. Error launching application on iPhone`

You're running `flutter run` instead of `flutter build ipa`. The simulator build doesn't produce an IPA. Use `build ipa` for shipping.

### `Could not parse iOS App Bundle's Info.plist`

`flutter build ios` produces an `.app` bundle (good for sim), but the IPA needs an archive. Use `flutter build ipa --release` instead.

### `error: exportArchive: No profiles for 'com.example.app' were found`

This bites users who switched away from automatic signing. Either go back to automatic signing in `ios/Runner.xcodeproj` or specify provisioning profiles in your `ExportOptions.plist` under the `provisioningProfiles` key.

### `Asset validation failed: Invalid Bundle. The bundle does not support arm64`

You built for the simulator (x86_64) instead of a real device (arm64). `flutter build ipa --release` produces arm64 by default; if you specified a `--target-platform`, remove it.

### `Apple is still processing`

Normal. Apple takes 5-15 minutes to process a TestFlight build after upload. Wait, or use the MySigner CLI which polls automatically.

---

## What About CI?

Both paths work in CI:

- **Vanilla path**: install `flutter`, install `xcode` (or use a macOS runner that has it), set ASC API key as a base64 secret, run the three commands.
- **MySigner path**: install with `gem install mysigner`, set `MYSIGNER_API_TOKEN`, `MYSIGNER_ORG_ID`, and `MYSIGNER_API_URL` as CI secrets, run `mysigner ship testflight`.

The MySigner path needs fewer secrets in your CI (one token vs Issuer ID + Key ID + .p8 file), and the `mysigner doctor` command works as a one-line smoke test before you trust a release pipeline.

---

## What This Doesn't Cover

- **Android side of Flutter shipping.** Different pipeline; see [How to upload to Play Store from command line](/docs/blog/upload-to-testflight-without-xcode) for the equivalent.
- **Code signing setup.** If your team hasn't ever shipped to TestFlight before, you'll need to set up certificates and profiles in Apple Developer Portal once. After that, the CLI flow works.
- **TestFlight beta groups and external testers.** Those are configured in App Store Connect; the CLI just uploads builds.

---

## TL;DR

Flutter to TestFlight without Xcode is either two commands (`flutter build ipa` + `xcrun altool`) or one (`mysigner ship testflight`). The IPA produced is identical either way; the difference is how much setup you maintain.

[Start free → mysigner.dev](https://mysigner.dev/users/sign_up)
