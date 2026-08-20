---
title: Authentication Commands
description: Login, logout, and manage your CLI authentication
order: 2
---

# Authentication Commands

Commands for authenticating the CLI and managing your account.

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner onboard` | First-time setup wizard (start here!) |
| `mysigner login` | Log in with an existing API token |
| `mysigner logout` | Log out and clear credentials |
| `mysigner status` | Check connection and credentials |
| `mysigner orgs` | List all your organizations |
| `mysigner switch` | Switch to a different organization |
| `mysigner config` | Show current CLI configuration |
| `mysigner version` | Show CLI version and system info |

---

## onboard

Interactive wizard for first-time setup. **Start here if you're new.**

### Usage

```bash
mysigner onboard
```

### What It Does

1. Guides you through creating an account (if needed)
2. Helps you create an organization
3. Walks you through generating an API token
4. Configures the CLI with your credentials
5. Optionally sets up App Store Connect credentials

### Example Session

```bash
$ mysigner onboard

🚀 My Signer Setup Guide
================================================================================

Welcome! Let's get you set up with My Signer.

Do you have a My Signer account?
  1. Yes, I have an account
  2. No, I need to sign up

Select (1-2): 1
...
```

---

## login

Log in with an existing API token. For experienced users who already have a token.

### Usage

```bash
mysigner login
```

### Description

Authenticates with the MySigner API using an API token. Your credentials are stored securely in `~/.mysigner/config.yml`.

> **Note:** API tokens are organization-specific. Each token only grants access to the organization it was created in.

### Example

```bash
$ mysigner login

🔐 My Signer Login
================================================================================

API URL: https://mysigner.dev
Press Enter to use default, or type custom URL: [Enter]

Your Email: developer@company.com

Don't have a token yet?
  1. Go to: https://mysigner.dev
  2. Navigate to: Your Organization → API Tokens
  3. Click 'Create Token'
  4. Copy the token (you'll only see it once!)

💡 Or run 'mysigner onboard' for step-by-step guidance

API Token: ************************************

Validating token and email...
✓ Token valid
Detecting organization...
✓ Organization detected: My Company
✓ Email validated: developer@company.com

================================================================================
✓ Successfully logged in!
================================================================================

Organization: My Company (ID: org_abc123)
Role: admin
Config saved to: ~/.mysigner/config.yml

🚀 Next steps:
  cd your-ios-project
  mysigner ship testflight

💡 Helpful commands:
  • mysigner doctor     - Check your environment
  • mysigner orgs       - List all organizations
  • mysigner switch     - Switch to another organization
```

---

## logout

Log out and clear all stored credentials.

### Usage

```bash
mysigner logout
```

### Example

```bash
$ mysigner logout

Are you sure you want to logout? (y/n) y
✓ Successfully logged out
Config file removed: ~/.mysigner/config.yml
```

---

## status

Check your connection, credentials, and App Store Connect setup.

### Usage

```bash
mysigner status
```

### Example Output

```bash
$ mysigner status

📊 My Signer Status

Configuration:
  API URL:         https://mysigner.dev
  User:            developer@company.com
  Encryption:      ✓ Enabled

Current Organization:
  Name:  My Company
  ID:    org_abc123
  Token: ms_t...5xyz

Connection:
  Status: ✓ Connected
  Role:   admin
  Members: 3

App Store Connect:
  ✓ Configured
  Team ID: ABC123XYZ
```

---

## orgs

List all organizations you're a member of.

### Usage

```bash
mysigner orgs
```

### Example Output

```bash
$ mysigner orgs

📋 Organizations

  ✓ My Company (current)
    ID: org_abc123 | Role: admin | Members: 3

  ⚠️ Side Project
    ID: org_def456 | Need token to access

Total: 2 organization(s)

Legend: ✓ = Has token | ⚠️ = Need token

💡 Tip: Use 'mysigner switch' to change organizations
```

---

## switch

Switch between organizations.

### Usage

```bash
mysigner switch
```

### Description

For multi-organization users. Switch to a different organization. If you don't have a token for the target organization, you'll be prompted to enter one.

### Example

```bash
$ mysigner switch

🔄 Switch Organization

Current organization:
  My Company (ID: org_abc123)

Available organizations:

  1. ✓ My Company (current)
      ID: org_abc123 | Token saved
  2. ⚠️ Side Project
      ID: org_def456 | Need token

Select organization (1-2, or 'q' to cancel): 2

⚠️ You don't have a token for 'Side Project' yet.

To switch to this organization:
  1. Go to: https://mysigner.dev/organizations/org_def456/api_tokens
  2. Generate a new API token
  3. Paste it below

Paste API token for 'Side Project' (or 'q' to cancel): ****
Validating token...
✓ Token validated successfully

✓ Successfully switched to: Side Project
```

---

## config

Show the current CLI configuration.

### Usage

```bash
mysigner config
```

### Example Output

```bash
$ mysigner config

⚙️  Configuration

  api_url             : https://mysigner.dev
  user_email          : developer@company.com
  current_organization: My Company (ID: org_abc123)
  current_token       : ms_t...5xyz

Config file: ~/.mysigner/config.yml
```

---

## version

Show CLI version and system information.

### Usage

```bash
mysigner version
```

### Example Output

```bash
$ mysigner version

My Signer CLI v{{cli_version}}

Ruby:        3.4.5 (arm64-darwin23)
Install:     /opt/homebrew/lib/ruby/gems/3.4.0/gems/mysigner-{{cli_version}}
Config:      ~/.mysigner/config.yml

Docs:        https://mysigner.dev/docs/commands
Support:     https://mysigner.dev/landing#contact
```

---

## Security Notes

- The CLI stores its config at `~/.mysigner/config.yml` (mode `0600`, owner-only)
- API tokens are encrypted at rest with AES-256-GCM. The encryption key lives in the macOS Keychain on macOS, or in a `0600` file at `~/.mysigner/.encryption_key` on Linux and Windows. The token is never on disk in plaintext on any platform.
- App Store Connect `.p8` keys, Google Play service-account JSON, and keystore passwords are not stored locally — they live on the MySigner server (encrypted at rest in the database) and are fetched / brokered through the server on demand
- Tokens are organization-specific and cannot access other organizations
- Use `mysigner switch` to add tokens for multiple organizations
- Never share your API token or commit it to version control
- In CI/CD, prefer the `MYSIGNER_API_TOKEN` env var (plus `MYSIGNER_ORG_ID`) so nothing is written to disk

## Related Commands

- [`doctor`](doctor) - Diagnose setup issues
- [`sync`](sync) - Sync data from App Store Connect
