---
title: doctor
description: Run health checks and diagnose setup issues
order: 20
---

# doctor

Run a comprehensive health check and diagnose common setup issues. If you're stuck, run this first!

## Usage

```bash
mysigner doctor [options]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--platform` | Check specific platform: ios, android, or all | `all` |

## What It Checks

### iOS Checks

| Check | Description |
|-------|-------------|
| Xcode | Xcode installation and version |
| Command Line Tools | Xcode command line tools installed |
| Upload Tools | altool and iTMSTransporter availability |
| MySigner Config | Login status and API connection |
| Signing Identity | Certificates in local Keychain |
| App Store Connect | ASC credentials configured |
| Disk Space | Sufficient disk space available |
| Network | Connection to Apple servers |
| Project | iOS project detection and bundle ID |
| Profiles | Required provisioning profiles |

### Android Checks

| Check | Description |
|-------|-------------|
| Java/JDK | Java installation and JAVA_HOME |
| Android SDK | ANDROID_HOME environment variable |
| Gradle | Gradle or gradlew availability |
| Google Play | Google Play credentials configured |
| Keystores | Active keystore for signing |
| Project | Android project detection |

---

## Example Output

```bash
$ mysigner doctor

🩺 My Signer Health Check
================================================================================

Checking Xcode...
  ✓ Xcode installed: Xcode 15.2

Checking Command Line Tools...
  ✓ Command Line Tools installed

Checking upload tools...
  ✓ xcrun altool available
  ✓ iTMSTransporter available (fallback)

Checking My Signer configuration...
  ✓ Logged in
  ✓ API connection working

Checking signing identity for team...
  ✓ Signing identity found for team ABC123XYZ

Checking App Store Connect credentials...
  ✓ App Store Connect configured
    Team ID: ABC123XYZ

Checking Xcode license...
  ✓ Xcode license accepted

Checking disk space...
  ✓ Sufficient disk space: 45% used

Checking network connectivity...
  ✓ Internet connection working

Checking current directory...
  ✓ Found Native iOS project: MyApp.xcworkspace

Checking organization resources...
  ✓ Certificates: 2
  ✓ Devices: 5
  ✓ Bundle IDs: 3
  ✓ Profiles: 4

Checking project signing setup...
  Project: MyApp
  Bundle ID: com.company.myapp

  Checking bundle ID registration...
  ✓ Bundle ID registered
  Checking provisioning profiles...
  ✓ App Store provisioning profile exists
  ✓ Development profile exists

Checking Android development environment...
  ✓ Java installed: openjdk version "17.0.9"
  ✓ JAVA_HOME: /opt/homebrew/opt/openjdk@17
  ✓ Android SDK: /Users/dev/Library/Android/sdk
  ✓ Gradle 8.2

Checking Google Play configuration...
  ✓ Google Play credentials configured
  ✓ Active keystore: Production Key

================================================================================
Health Report
================================================================================

🎉 All checks passed! You're good to go!

Try: mysigner ship testflight
```

---

## Auto-Fix Features

Doctor can automatically fix common issues:

### App Store Connect Setup

If ASC credentials aren't configured:

```bash
Checking App Store Connect credentials...
  ✗ App Store Connect not configured

Would you like to set it up now? [Y/n] y

📱 App Store Connect API Key Setup

Let's set up your App Store Connect credentials.

Step 1: Create an API Key (if you don't have one)

1. Go to:
   https://appstoreconnect.apple.com/access/api

2. Click the '+' button to create a new key
...
```

### Provisioning Profile Creation

If required profiles are missing:

```bash
Checking provisioning profiles...
  ✗ No App Store provisioning profile for com.company.myapp

Create App Store profile automatically? [Y/n] y

Creating App Store profile for com.company.myapp...
  Syncing organization resources...
  ✓ Sync complete
  Creating IOS_APP_STORE profile...
  ✓ Created profile: MyApp AppStore
    UUID: abc123-def456
    Expires: 2027-01-15
  Downloading profile...
  ✓ Profile installed to Xcode
```

### Certificate Guidance

If certificates are missing:

```bash
Checking signing identity for team...
  ✗ No signing identity for team ABC123XYZ

  CRITICAL: You need to sign into Xcode and download certificates:
    1. Open Xcode → Settings → Accounts
    2. Verify you're signed in with your Apple ID
    3. Select team 'ABC123XYZ'
    4. Click 'Download Manual Profiles' (or 'Manage Certificates')
    5. The certificate should appear in keychain
```

### JAVA_HOME Fix

If JAVA_HOME is misconfigured:

```bash
Checking Java/JDK...
  ✓ Java installed: openjdk version "17.0.9"
  ✗ JAVA_HOME invalid: /old/path/to/java
  💡 Detected valid Java at: /opt/homebrew/opt/openjdk@17

  Would you like to fix JAVA_HOME in your shell config? [Y/n] y

  ✓ Updated JAVA_HOME in ~/.zshrc

  To apply now, run:
    source ~/.zshrc

  Or restart your terminal.
```

---

## Common Issues and Fixes

### No Signing Identity

**Problem:**
```
✗ No signing identity for team ABC123XYZ
```

**Fix:**
1. Open Xcode → Settings → Accounts
2. Select your Apple ID
3. Click your team → Manage Certificates
4. Create or download certificates

### Bundle ID Not Registered

**Problem:**
```
✗ Bundle ID 'com.company.myapp' not registered in App Store Connect
```

**Fix:**
```bash
mysigner bundleid register com.company.myapp
mysigner sync ios
```

### No Active Keystore (Android)

**Problem:**
```
ℹ️ No Android keystores
```

**Fix:**
```bash
mysigner keystore upload ~/path/to/release.jks
```

### Token Invalid

**Problem:**
```
✗ Token is invalid or expired
```

**Fix:**
```bash
mysigner onboard
# Or
mysigner login
```

---

## Platform-Specific Checks

### iOS Only

```bash
mysigner doctor --platform ios
```

### Android Only

```bash
mysigner doctor --platform android
```

---

## When to Run Doctor

Run doctor when:
- Setting up MySigner for the first time
- Build or signing fails unexpectedly
- After changing team or credentials
- When troubleshooting any issue

---

## Related Commands

- [`status`](auth#status) - Quick connection check
- [`sync`](sync) - Sync from app stores
- [`signing`](signing) - Configure code signing
