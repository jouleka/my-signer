---
title: signing
description: Configure code signing in Xcode projects
order: 11
---

# signing

Configure manual code signing in your Xcode project.

> **Note:** Most users should use **Automatic Signing**. Xcode handles everything and works with `mysigner build` and `mysigner ship`. Only use this command if you need manual signing control.

## Usage

```bash
mysigner signing configure [options]
```

## Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--target` | `-t` | Configure specific target only | Main target |
| `--all-targets` | | Configure all app and extension targets | false |

---

## When to Use Manual Signing

### Use Automatic Signing (Default) When:
- You're the only developer
- Standard app without special requirements
- Just want things to work

### Use Manual Signing When:
- Sharing profiles across a team
- Specific entitlements requirements
- App extensions with complex signing
- CI/CD with shared certificates
- Enterprise distribution
- Need specific profile UUIDs

---

## How It Works

The signing configure wizard:

1. **Detects** your Xcode project and targets
2. **Shows** current signing configuration
3. **Lists** available team IDs
4. **Helps** select the right provisioning profile
5. **Applies** configuration to your Xcode project
6. **Validates** the setup works

---

## Examples

### Configure Main App

```bash
$ mysigner signing configure

🔍 Detecting project...

✓ Found: MyApp.xcworkspace (Native iOS)

📋 Current Signing Configuration

  Target: MyApp
  Signing Style: Manual
  Team ID: ABC123XYZ
  Profile: (none)

🔐 Configuring Manual Signing

Step 1: Select Development Team

Available teams:
  1. ABC123XYZ - My Company

Select team (1): 1

Step 2: Select Provisioning Profile

Available profiles for com.company.myapp:
  1. MyApp AppStore (IOS_APP_STORE) - Expires 2027-01-15
  2. MyApp Development (IOS_APP_DEVELOPMENT) - Expires 2027-01-15

Select profile (1-2): 1

Applying configuration to Xcode project...

✓ Signing configured successfully!

  Target: MyApp
  Team ID: ABC123XYZ
  Profile: MyApp AppStore (abc123-def456)
  Signing Style: Manual

Next: mysigner build
```

### Configure Specific Target

```bash
$ mysigner signing configure --target MyWidget

🔍 Detecting project...

Configuring target: MyWidget
...
```

### Configure All Targets

```bash
$ mysigner signing configure --all-targets

🔍 Detecting project...

Found 3 targets:
  1. MyApp (Application)
  2. MyWidget (App Extension)
  3. MyNotifications (App Extension)

Configuring all targets...
...
```

---

## Automatic Signing Detection

If your project uses automatic signing:

```bash
$ mysigner signing configure

⚠️ Project uses Automatic signing

Your project is configured for Automatic signing, which means:
  • Xcode manages profiles automatically
  • No manual profile configuration needed
  • Team ID is all you need

Current Team ID: ABC123XYZ

You can build with: mysigner build
```

---

## Configuration Files

### What Gets Modified

The wizard modifies your `.xcodeproj` or `.xcworkspace`:

- `CODE_SIGN_STYLE` → `Manual`
- `DEVELOPMENT_TEAM` → Your team ID
- `PROVISIONING_PROFILE_SPECIFIER` → Profile name
- `CODE_SIGN_IDENTITY` → Certificate type

### Backup

Your Xcode project is automatically backed up before changes. The backup is stored in the same directory with a timestamp.

---

## Troubleshooting

### "No Profiles Found"

```bash
No provisioning profiles found for com.company.myapp
```

**Fix:**
1. Run doctor to create profiles:
   ```bash
   mysigner doctor
   ```

2. Or sync from Apple:
   ```bash
   mysigner sync ios
   ```

3. Or check bundle ID matches:
   ```bash
   mysigner bundleid list
   ```

### "Team ID Not Set"

```bash
No team ID found in project or API
```

**Fix:**
1. Set team ID in Xcode project settings
2. Or configure in MySigner dashboard
3. Or specify with `--team` option

### Profile Expired

```bash
Profile MyApp AppStore is expired
```

**Fix:**
1. Regenerate in App Store Connect
2. Or run `mysigner doctor` to auto-create
3. Then sync: `mysigner sync ios`

---

## Manual vs Automatic Signing

| Aspect | Automatic | Manual |
|--------|-----------|--------|
| Profile management | Xcode handles | You manage |
| Team configuration | Just team ID | Team + profile |
| Extensions | Auto-configured | Each needs config |
| CI/CD | Works with team ID | Needs profile UUIDs |
| Debugging | Less control | Full control |

### Switching to Manual

If you need to switch from automatic to manual:

```bash
mysigner signing configure
# Follow the wizard
```

### Switching to Automatic

In Xcode:
1. Select your target
2. Go to Signing & Capabilities
3. Check "Automatically manage signing"

---

## Related Commands

- [`profiles`](profiles) - List and download profiles
- [`certificates`](certificates) - Manage certificates
- [`doctor`](doctor) - Auto-create missing profiles
- [`build`](build) - Build with configured signing
