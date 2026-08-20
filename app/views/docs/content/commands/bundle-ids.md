---
title: bundleid
description: List and register bundle identifiers (App IDs)
order: 10
---

# bundleid

List and register iOS bundle identifiers (App IDs) in App Store Connect.

## What Is a Bundle ID?

A bundle identifier is a unique identifier for your app, following reverse domain notation:
- `com.company.myapp` - Main app
- `com.company.myapp.widget` - App extension

Every iOS app needs a registered bundle ID before:
- Creating provisioning profiles
- Uploading to App Store Connect
- Distributing via TestFlight

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner bundleid list` | List all registered bundle IDs |
| `mysigner bundleid register` | Register a new bundle ID |
| `mysigner bundleid delete` | Delete a registered bundle ID |

---

## bundleid list

List all registered bundle identifiers.

### Usage

```bash
mysigner bundleid list
```

### Example

```bash
$ mysigner bundleid list

📦 Bundle IDs

  • MyApp
    Identifier: com.company.myapp

  • MyApp Widget
    Identifier: com.company.myapp.widget

  • MyApp Notifications
    Identifier: com.company.myapp.notifications

Total: 3 bundle ID(s)
```

---

## bundleid register

Register a new bundle identifier in App Store Connect.

### Usage

```bash
mysigner bundleid register IDENTIFIER [NAME]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `IDENTIFIER` | Bundle ID (e.g., com.company.myapp) | Yes |
| `NAME` | Display name (defaults to last segment) | No |

### Format Requirements

Bundle IDs must:
- Start with a letter
- Use reverse domain notation (e.g., `com.company.app`)
- Contain only letters, numbers, hyphens, and periods

### Examples

```bash
# Register main app
mysigner bundleid register com.company.myapp

# Register with custom name
mysigner bundleid register com.company.myapp "My Awesome App"

# Register an extension
mysigner bundleid register com.company.myapp.widget "My Widget"
```

### Example Output

```bash
$ mysigner bundleid register com.company.newapp "New App"

🔗 Registering Bundle ID...

  Identifier: com.company.newapp
  Name: New App

✓ Bundle ID registered successfully!

Details:
  Identifier: com.company.newapp
  Name: New App

Next steps:
  1. Sync to update local cache: mysigner sync ios
  2. Create a provisioning profile: mysigner doctor (will auto-create)
  3. Or run: mysigner signing configure
```

### Already Exists?

If the bundle ID already exists:

```bash
$ mysigner bundleid register com.company.myapp

ℹ️ Bundle ID already registered: com.company.myapp

This Bundle ID already exists in App Store Connect.
Run 'mysigner sync ios' to update your local cache.
```

---

## bundleid delete

Delete a bundle identifier from App Store Connect.

### Usage

```bash
mysigner bundleid delete IDENTIFIER
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `IDENTIFIER` | Bundle ID to delete (e.g., com.company.myapp) | Yes |

### Example

```bash
$ mysigner bundleid delete com.company.oldapp

🔗 Deleting Bundle ID...

  Identifier: com.company.oldapp

✓ Bundle ID deleted: com.company.oldapp
```

> **Note:** A Bundle ID can't be deleted while it's still attached to active resources in App Store Connect (provisioning profiles, apps, capabilities). Remove those first, then re-run `mysigner bundleid delete`.

---

## When to Register Bundle IDs

### Before Your First Build

Register your bundle ID before:
1. Building for App Store/TestFlight
2. Creating provisioning profiles
3. Running `mysigner ship`

### For App Extensions

Each extension needs its own bundle ID with the parent app's bundle ID as a prefix:

| Component | Bundle ID |
|-----------|-----------|
| Main app | `com.company.myapp` |
| Widget | `com.company.myapp.widget` |
| Notifications | `com.company.myapp.notifications` |
| Watch app | `com.company.myapp.watchkitapp` |
| Intents | `com.company.myapp.intents` |

---

## Capabilities

Bundle IDs can have capabilities enabled (like Push Notifications, Sign in with Apple, etc.). Currently, manage capabilities via:

1. **Apple Developer Portal**  
   https://developer.apple.com/account/resources/identifiers/list

2. **MySigner Dashboard**  
   View and manage capabilities in the web UI

---

## Troubleshooting

### "Bundle ID Not Found" Errors

When building, you might see:
```
Bundle ID 'com.company.myapp' not registered in App Store Connect
```

**Fix:**
```bash
# Register the bundle ID
mysigner bundleid register com.company.myapp

# Sync to update local cache
mysigner sync ios
```

### Invalid Format

```bash
$ mysigner bundleid register my-app

Error: Invalid Bundle ID format: my-app

Bundle IDs must:
  • Start with a letter
  • Use reverse domain notation (e.g., com.company.app)
  • Contain only letters, numbers, hyphens, and periods
```

**Fix:** Use proper format:
```bash
mysigner bundleid register com.company.my-app
```

### Duplicate Bundle ID

```bash
$ mysigner bundleid register com.company.myapp

ℹ️ Bundle ID already registered: com.company.myapp
```

This isn't an error - the bundle ID is already available. Just sync:
```bash
mysigner sync ios
```

---

## Related Commands

- [`apps`](apps) - List apps from App Store Connect
- [`profiles`](profiles) - Manage provisioning profiles
- [`doctor`](doctor) - Auto-detect and fix issues
- [`sync`](sync) - Sync from App Store Connect
