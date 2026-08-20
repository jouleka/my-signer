---
title: apps
description: List apps from App Store Connect and Google Play
order: 22
---

# apps

List all apps from your connected iOS (App Store Connect) and Android (Google Play) accounts.

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner apps` | List all apps from both platforms |

---

## apps

List all apps registered with your organization.

### Usage

```bash
mysigner apps [options]
```

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--platform` | | Filter by platform: `ios`, `android` | All |
| `--search` | `-q` | Search by name or bundle ID | |
| `--page` | | Page number | 1 |
| `--per-page` | | Apps per page | 50 |

### Examples

```bash
# List all apps
mysigner apps

# List iOS apps only
mysigner apps --platform ios

# List Android apps only
mysigner apps --platform android

# Search for specific app
mysigner apps --search myapp
```

### Example Output

```bash
$ mysigner apps

📱 iOS Apps

  • My Awesome App
    Bundle ID: com.company.myapp

  • My Other App
    Bundle ID: com.company.otherapp

🤖 Android Apps

  • My Awesome App
    Package: com.company.myapp

  • My Android App
    Package: com.company.android
```

### Filtered Output

```bash
$ mysigner apps --platform ios

📱 iOS Apps

  • My Awesome App
    Bundle ID: com.company.myapp

  • My Other App
    Bundle ID: com.company.otherapp
```

---

## App Information

### iOS Apps

For iOS apps, you'll see:
- **Name**: App display name
- **Bundle ID**: The unique identifier (e.g., `com.company.myapp`)

### Android Apps

For Android apps, you'll see:
- **Name**: App display name
- **Package**: The package name (e.g., `com.company.myapp`)

---

## Adding New Apps

### iOS Apps

iOS apps are automatically synced from App Store Connect. To add a new app:

1. Create the app in [App Store Connect](https://appstoreconnect.apple.com)
2. Run `mysigner sync ios` to update

Or register a new bundle ID:

```bash
mysigner bundleid register com.company.newapp "New App"
mysigner sync ios
```

### Android Apps

Register an Android app with:

```bash
mysigner android add com.company.newapp --name "New App"
```

See the [android](android) documentation for more details.

---

## Related Commands

- [`bundleid`](bundle-ids) - Manage iOS bundle identifiers
- [`android`](android) - Manage Android apps and builds
- [`sync`](sync) - Sync from App Store Connect and Google Play
