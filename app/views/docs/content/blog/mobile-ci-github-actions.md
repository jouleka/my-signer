---
title: Mobile App CI/CD with GitHub Actions (iOS + Android, 2026)
description: A working GitHub Actions setup for shipping iOS and Android apps to TestFlight and Play Console. Real config files, real secrets, real costs.
order: 7
---

# Mobile App CI/CD with GitHub Actions

**Quick answer:** Use `macos-latest` for iOS jobs, `ubuntu-latest` for Android. Sign with App Store Connect API keys for iOS and a base64-encoded keystore for Android. Run them in parallel; both halves of a release usually finish in 10-15 minutes. Full configs below.

This article assumes you're shipping an iOS + Android app and you want releases to happen via `git push` (or a release tag), not manual button clicks. The configs below are working examples from real production setups, simplified.

---

## GitHub Actions Costs for Mobile

Important reality check before you start:

- **macOS runners cost 10x what Linux runners cost** in GitHub-hosted compute. iOS jobs add up fast.
- **Free tier**: 2,000 minutes/month for private repos, but **macOS minutes count 10x**. So you effectively get 200 macOS minutes/month free.
- **Pro tier ($4/mo)**: 3,000 minutes (300 macOS).
- **Team tier ($4/user/mo)**: same minutes pool with shared org billing.

For a small team, a typical iOS release run (build + upload + poll Apple) takes 10-15 minutes. If you ship weekly, that's 40-60 macOS minutes per month. Comfortably inside even the Free tier.

If you ship daily or have heavy UI tests, you'll burn through quickly. Self-hosting a Mac mini runner is a one-time hardware cost that pays back in 6-12 months.

---

## Repository Structure (Recommended)

```
.github/workflows/
  ios-testflight.yml     # On tag push, ship iOS to TestFlight
  android-internal.yml   # On tag push, ship Android to internal track
  ci.yml                 # On every PR, run tests (no shipping)
```

Keep build/test in one file and shipping in another. Tests run on every PR (cheap, Linux runners). Shipping runs only on tags (expensive macOS, deliberate).

---

## iOS: TestFlight via GitHub Actions

`.github/workflows/ios-testflight.yml`:

```yaml
name: Ship iOS to TestFlight

on:
  push:
    tags:
      - "v*"

jobs:
  ship:
    runs-on: macos-latest
    timeout-minutes: 30

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby (for mysigner CLI)
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.4

      - name: Install mysigner CLI
        run: gem install mysigner

      - name: Ship to TestFlight
        run: mysigner ship testflight
        env:
          MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
          MYSIGNER_ORG_ID:    ${{ secrets.MYSIGNER_ORG_ID }}
          MYSIGNER_API_URL:   https://mysigner.dev
```

That's it. Three secrets, one job, ~12 minutes.

The MySigner dashboard holds your App Store Connect API key (encrypted at rest), so you don't need to manage the `.p8`, Issuer ID, or Key ID as CI secrets.

### What if you don't use MySigner?

You'll need a longer config that handles ASC API key setup, certificate import, and the `xcodebuild archive` → `xcrun altool` flow manually:

```yaml
name: Ship iOS to TestFlight (vanilla)

on:
  push:
    tags:
      - "v*"

jobs:
  ship:
    runs-on: macos-latest
    timeout-minutes: 30

    steps:
      - uses: actions/checkout@v4

      - name: Set up Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app

      - name: Install ASC API key
        run: |
          mkdir -p ~/.appstoreconnect/private_keys
          echo "${{ secrets.ASC_API_KEY_BASE64 }}" | base64 --decode \
            > ~/.appstoreconnect/private_keys/AuthKey_${{ secrets.ASC_API_KEY_ID }}.p8

      - name: Import certificate
        run: |
          echo "${{ secrets.DIST_CERT_P12_BASE64 }}" | base64 --decode > cert.p12
          security create-keychain -p "" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "" build.keychain
          security import cert.p12 -k build.keychain -P "${{ secrets.P12_PASSWORD }}" \
            -T /usr/bin/codesign -T /usr/bin/security
          security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain

      - name: Build archive
        run: |
          xcodebuild archive \
            -workspace YourApp.xcworkspace \
            -scheme YourApp \
            -destination 'generic/platform=iOS' \
            -archivePath build/YourApp.xcarchive \
            -allowProvisioningUpdates

      - name: Export IPA
        run: |
          xcodebuild -exportArchive \
            -archivePath build/YourApp.xcarchive \
            -exportPath build \
            -exportOptionsPlist ExportOptions.plist \
            -allowProvisioningUpdates

      - name: Upload to TestFlight
        run: |
          xcrun altool --upload-app \
            --type ios \
            --file build/YourApp.ipa \
            --apiKey ${{ secrets.ASC_API_KEY_ID }} \
            --apiIssuer ${{ secrets.ASC_ISSUER_ID }}
```

Five secrets to manage:

- `ASC_API_KEY_BASE64`: base64 of your `.p8` file
- `ASC_API_KEY_ID`: 10-char key ID
- `ASC_ISSUER_ID`: UUID
- `DIST_CERT_P12_BASE64`: base64 of your Apple Distribution `.p12` export
- `P12_PASSWORD`: password on the `.p12`

Plus an `ExportOptions.plist` checked into your repo.

---

## Android: Play Internal Track via GitHub Actions

`.github/workflows/android-internal.yml`:

```yaml
name: Ship Android to Internal Track

on:
  push:
    tags:
      - "v*"

jobs:
  ship:
    runs-on: ubuntu-latest
    timeout-minutes: 20

    steps:
      - uses: actions/checkout@v4

      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.4

      - name: Install mysigner CLI
        run: gem install mysigner

      - name: Ship to Play Internal
        run: mysigner ship internal --platform android
        env:
          MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
          MYSIGNER_ORG_ID:    ${{ secrets.MYSIGNER_ORG_ID }}
          MYSIGNER_API_URL:   https://mysigner.dev
```

Linux runner = 1/10th the cost of macOS. The keystore lives in the MySigner dashboard, so no base64-encoded secret to manage.

### Vanilla Android version (no MySigner)

```yaml
- name: Decode keystore
  run: |
    echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > release.keystore

- name: Build AAB
  run: ./gradlew bundleRelease
  env:
    MYSIGNER_STORE_FILE: ${{ github.workspace }}/release.keystore
    MYSIGNER_STORE_PASSWORD: ${{ secrets.STORE_PASSWORD }}
    MYSIGNER_KEY_ALIAS: release
    MYSIGNER_KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}

- name: Upload to Play Internal
  uses: r0adkll/upload-google-play@v1
  with:
    serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
    packageName: com.example.app
    releaseFiles: app/build/outputs/bundle/release/app-release.aab
    track: internal
```

Five secrets, plus a Gradle config that reads them. The `r0adkll/upload-google-play` action is community-maintained and the most-used Android-upload action.

---

## Parallel iOS + Android Releases

If you want both platforms shipped on the same tag, use one workflow with two jobs:

```yaml
name: Ship Release

on:
  push:
    tags:
      - "v*"

jobs:
  ios:
    runs-on: macos-latest
    steps:
      # ... iOS shipping steps
  android:
    runs-on: ubuntu-latest
    steps:
      # ... Android shipping steps
```

They run in parallel. Total wall time is whichever is slower (usually iOS, because Apple processes uploads for 5-15 minutes).

---

## Secrets You'll Need (Full List)

**Minimum with MySigner:**

- `MYSIGNER_API_TOKEN`
- `MYSIGNER_ORG_ID`

**Minimum vanilla iOS:**

- `ASC_API_KEY_BASE64`
- `ASC_API_KEY_ID`
- `ASC_ISSUER_ID`
- `DIST_CERT_P12_BASE64`
- `P12_PASSWORD`

**Minimum vanilla Android:**

- `KEYSTORE_BASE64`
- `STORE_PASSWORD`
- `KEY_PASSWORD`
- `PLAY_SERVICE_ACCOUNT_JSON`

---

## Common CI Failures

### `error: No profile for team 'XXXXXXXXXX' matching 'com.example.app' found`

The CI runner doesn't have your provisioning profile. Either use `-allowProvisioningUpdates` (automatic signing fetches profiles via Xcode) or download profiles via `fastlane match` / a base64'd profile secret.

### `Code Signing Error: No signing certificate "iOS Distribution" found`

You haven't imported the certificate into the runner's keychain. See the "Import certificate" step in the vanilla iOS config above.

### `Keystore was tampered with, or password was incorrect`

The `KEYSTORE_BASE64` secret is wrong, or `STORE_PASSWORD` is wrong. Test locally with the same env vars to isolate.

### `iOS 26.4 is not installed`

The macOS runner image doesn't have iOS device platform for that SDK installed. GitHub keeps `macos-latest` updated, but if you're pinned to an older runner image, you may need to pick a newer one or stick to the SDK version that runner has.

### macOS runner not available (queued)

GitHub's macOS runner pool is smaller than Linux. Free-tier macOS jobs can queue for a few minutes during peak times. Pro tier prioritizes you.

---

## When Self-Hosted Runners Make Sense

Switch to self-hosted when:

- You're spending >$30/mo on GitHub macOS minutes.
- You need iOS builds <2 minutes (self-hosted Mac mini boots fast and skips runner image setup).
- You need access to a specific Xcode beta version GitHub hasn't shipped yet.

A Mac mini M4 (~$600 + display) pays for itself in 12-18 months at moderate shipping cadence.

---

## TL;DR

Two jobs, one tag, parallel iOS + Android. With MySigner, three secrets total. Without, ~9 secrets and ~150 more lines of YAML. Pick based on how much CI complexity you want to maintain.

[Start free → mysigner.dev](https://mysigner.dev/users/sign_up)
