---
title: merchant-ids
description: List and manage Apple Pay Merchant IDs
order: 12
---

# merchant-ids

List and manage Apple Pay Merchant IDs for your iOS apps.

## What Is a Merchant ID?

A Merchant ID is a unique identifier that represents you as a merchant accepting Apple Pay payments. It's required for apps that process Apple Pay transactions.

Merchant IDs must:
- Start with `merchant.` prefix
- Use reverse domain notation (e.g., `merchant.com.company.myapp`)

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner merchant-ids` | List all merchant IDs |
| `mysigner merchant-id create` | Create a new merchant ID |
| `mysigner merchant-id delete` | Delete a merchant ID |

---

## merchant-ids

List all registered Apple Pay Merchant IDs.

### Usage

```bash
mysigner merchant-ids [options]
```

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--search` | `-q` | Search by identifier or name | |
| `--page` | | Page number | 1 |
| `--per-page` | | Items per page | 50 |

### Example

```bash
$ mysigner merchant-ids

💳 Merchant IDs

  • My App Payments
    Identifier: merchant.com.company.myapp

  • Store Checkout
    Identifier: merchant.com.company.store

Total: 2 merchant ID(s)
```

---

## merchant-id create

Create a new Apple Pay Merchant ID.

### Usage

```bash
mysigner merchant-id create IDENTIFIER [--name NAME]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `IDENTIFIER` | Merchant ID (must start with `merchant.`) | Yes |

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--name` | `-n` | Display name | Identifier value |

### Format Requirements

Merchant IDs must:
- Start with `merchant.` prefix
- Use reverse domain notation
- Contain only letters, numbers, hyphens, and periods

### Examples

```bash
# Create merchant ID with auto-generated name
mysigner merchant-id create merchant.com.company.myapp

# Create with custom name
mysigner merchant-id create merchant.com.company.myapp --name "My App Payments"
```

### Example Output

```bash
$ mysigner merchant-id create merchant.com.company.myapp --name "My App Payments"

💳 Creating Merchant ID...

  Identifier: merchant.com.company.myapp
  Name: My App Payments

✓ Merchant ID created successfully!

Next steps:
  1. Configure Apple Pay in Xcode under Signing & Capabilities
  2. Set up your payment processor with this Merchant ID
  3. Run: mysigner sync ios
```

---

## merchant-id delete

Delete a Merchant ID from your Apple Developer account.

### Usage

```bash
mysigner merchant-id delete IDENTIFIER
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `IDENTIFIER` | Merchant ID to delete | Yes |

### Example

```bash
$ mysigner merchant-id delete merchant.com.company.oldapp

💳 Deleting Merchant ID...

  Identifier: merchant.com.company.oldapp

✓ Merchant ID deleted: merchant.com.company.oldapp
```

---

## Setting Up Apple Pay

After creating a Merchant ID:

1. **Enable Apple Pay capability** in Xcode
   Target → Signing & Capabilities → + Capability → Apple Pay

2. **Select your Merchant ID** in the capability settings

3. **Configure with your payment processor**
   Most processors require you to generate a payment processing certificate

---

## Related Commands

- [`bundleid`](bundle-ids) - Manage bundle identifiers
- [`profiles`](profiles) - Manage provisioning profiles
- [`sync`](sync) - Sync from App Store Connect
