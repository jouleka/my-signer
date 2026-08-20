---
title: validate
description: Validate signing configuration on the server
order: 19
---

# validate

Check if your bundle ID, certificate, and provisioning profile exist and are valid on the MySigner server before starting a build.

## Why Validate?

The CLI does local keychain/certificate validation, but doesn't check if your signing assets exist on the server. This catches common errors before a build starts:

- "Forgot to sync" after renewing certificates
- Expired provisioning profiles
- Missing bundle ID registrations

---

## Usage

```bash
mysigner validate [options]
```

## Options

| Option | Alias | Description | Required |
|--------|-------|-------------|----------|
| `--bundle-id` | `-b` | Bundle identifier (e.g., com.example.app) | Yes* |
| `--type` | `-t` | Signing type: development, appstore, adhoc, inhouse | Yes |

*Bundle ID is auto-detected from your Xcode project if not provided.

## Signing Types

| Type | Use Case |
|------|----------|
| `development` | Running on test devices |
| `appstore` | App Store / TestFlight distribution |
| `adhoc` | Ad-hoc distribution (enterprise/testing) |
| `inhouse` | Enterprise in-house distribution |

---

## Examples

### Validate Development Signing

```bash
$ mysigner validate --bundle-id com.example.app --type development

🔍 Validating signing configuration...

  Bundle ID: com.example.app
  Type:      development

  ✓ Bundle id: Bundle ID registered
  ✓ Certificate: Valid certificate found
  ✓ Profile: Provisioning profile valid

✓ All checks passed! Signing configuration is valid.
```

### When Validation Fails

```bash
$ mysigner validate -b com.example.app -t appstore

🔍 Validating signing configuration...

  Bundle ID: com.example.app
  Type:      appstore

  ✓ Bundle id: Bundle ID registered
  ✗ Certificate: Certificate expired
  ✗ Profile: No matching profile

✗ Validation failed. Some checks did not pass.

💡 Suggestions:
   → Renew your certificate in Apple Developer Portal
   → Run mysigner sync ios to regenerate profiles
```

### Auto-Detect Bundle ID

When run from a directory containing an Xcode project, the bundle ID is auto-detected:

```bash
$ cd ~/Projects/MyApp
$ mysigner validate --type development

🔍 Validating signing configuration...

  Bundle ID: com.example.myapp
  Type:      development

  ✓ Bundle id: Bundle ID registered
  ✓ Certificate: Valid certificate found
  ✓ Profile: Provisioning profile valid

✓ All checks passed! Signing configuration is valid.
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All checks passed |
| `1` | One or more checks failed |

This makes `validate` useful in CI/CD pipelines:

```bash
# Fail the pipeline early if signing isn't configured
mysigner validate -b com.example.app -t appstore || exit 1
mysigner ship appstore
```

---

## What Gets Checked

| Check | Description |
|-------|-------------|
| **Bundle ID** | Is the bundle identifier registered on the server? |
| **Certificate** | Is there a valid, non-expired signing certificate? |
| **Profile** | Is there a matching provisioning profile for this bundle ID and type? |

---

## Troubleshooting

### "Bundle ID is required"

Either provide `--bundle-id` or run from a directory with an Xcode project:

```bash
mysigner validate --bundle-id com.example.app --type development
```

### Checks Failing

If checks fail, follow the suggestions provided. Common fixes:

```bash
# Sync to refresh data from Apple
mysigner sync ios

# Check what's registered
mysigner bundleid list
mysigner certificates
mysigner profiles
```

---

## Related Commands

- [`doctor`](doctor) - Run full health check with auto-fix
- [`sync`](sync) - Sync data from Apple Developer Portal
- [`profiles`](profiles) - Manage provisioning profiles
- [`certificates`](certificates) - Manage signing certificates
