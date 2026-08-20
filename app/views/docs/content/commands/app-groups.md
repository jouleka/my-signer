---
title: app-groups
description: List and manage App Groups for data sharing between apps
order: 13
---

# app-groups

List and manage App Groups for sharing data between your apps and extensions.

## What Is an App Group?

App Groups allow multiple apps and app extensions from the same developer to share data. Common use cases include:

- Sharing data between an app and its widget
- Sharing data between an app and a Today Extension
- Sharing data between an app and a Watch app

App Group identifiers must:
- Start with `group.` prefix
- Use reverse domain notation (e.g., `group.com.company.myapp`)

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner app-groups` | List all app groups |
| `mysigner app-group register` | Register an existing app group |
| `mysigner app-group delete` | Remove an app group from My Signer |

> **Note:** Apple doesn't provide an API to create App Groups directly. You must first create the App Group in the [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list/applicationGroup), then register it with My Signer.

---

## app-groups

List all registered App Groups.

### Usage

```bash
mysigner app-groups [options]
```

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--search` | `-q` | Search by identifier or name | |
| `--page` | | Page number | 1 |
| `--per-page` | | Items per page | 50 |

### Example

```bash
$ mysigner app-groups

📦 App Groups

  • group.com.company.myapp
    Name: My App Shared Data

  • group.com.company.myapp.widget
    Name: Widget Data

Page 1 of 1 (2 total)
```

---

## app-group register

Register an existing App Group from your Apple Developer account with My Signer.

### Usage

```bash
mysigner app-group register IDENTIFIER [--name NAME]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `IDENTIFIER` | App Group ID (must start with `group.`) | Yes |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--name` | Display name | Last segment of identifier |

### Prerequisites

Before registering, you must first create the App Group in the Apple Developer Portal:

1. Go to [Identifiers](https://developer.apple.com/account/resources/identifiers/list/applicationGroup)
2. Click the "+" button
3. Select "App Groups"
4. Enter your identifier (e.g., `group.com.company.myapp`)
5. Click "Register"

### Examples

```bash
# Register app group
mysigner app-group register group.com.company.myapp

# Register with custom name
mysigner app-group register group.com.company.myapp --name "My App Shared Data"
```

### Example Output

```bash
$ mysigner app-group register group.com.company.myapp --name "My App Shared Data"

📦 Registering App Group...

✓ App Group registered!

  Identifier: group.com.company.myapp
  Name: My App Shared Data

  Remember: This only registers the App Group in My Signer.
  Make sure it exists in Apple Developer Portal.
```

---

## app-group delete

Remove an App Group from My Signer's tracking.

### Usage

```bash
mysigner app-group delete IDENTIFIER
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `IDENTIFIER` | App Group ID to remove | Yes |

### Example

```bash
$ mysigner app-group delete group.com.company.oldapp

📦 Removing App Group...

✓ App Group removed from My Signer: group.com.company.oldapp

  Note: The App Group still exists in Apple Developer Portal.
  Delete it manually if needed.
```

---

## Using App Groups in Xcode

After registering an App Group:

1. **Enable App Groups capability**
   Target → Signing & Capabilities → + Capability → App Groups

2. **Select your App Group** from the list

3. **Access shared data** using:
   ```swift
   let defaults = UserDefaults(suiteName: "group.com.company.myapp")
   let containerURL = FileManager.default.containerURL(
       forSecurityApplicationGroupIdentifier: "group.com.company.myapp"
   )
   ```

---

## Related Commands

- [`bundleid`](bundle-ids) - Manage bundle identifiers
- [`profiles`](profiles) - Manage provisioning profiles
- [`sync`](sync) - Sync from App Store Connect
