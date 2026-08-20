---
title: certificates
description: List and manage signing certificates
order: 9
---

# certificates

List and manage iOS code signing certificates.

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner certificates` | List certificates from App Store Connect |
| `mysigner certificate check` | Check certificates in local Keychain |
| `mysigner certificate download ID` | Download a certificate |

---

## Understanding Certificates

### Certificate Types

| Type | Use Case |
|------|----------|
| `DEVELOPMENT` | Signing development builds for testing |
| `DISTRIBUTION` | Signing production builds for App Store/TestFlight |

You need:
- **Apple Development** certificate for development builds
- **Apple Distribution** certificate for App Store/TestFlight

### Where Certificates Live

| Location | Purpose |
|----------|---------|
| **App Store Connect** | Stored in the cloud, synced by MySigner |
| **Local Keychain** | Installed on your Mac for Xcode to use |

> **Important:** Certificates must be installed in your local Keychain for Xcode to sign apps. The private key must also be present.

---

## certificates

List all signing certificates from App Store Connect.

### Usage

```bash
mysigner certificates [options]
```

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--type` | `-p` | Filter by type: DEVELOPMENT, DISTRIBUTION | All |
| `--status` | `-s` | Filter by status: ACTIVE, EXPIRED, REVOKED | All |
| `--search` | `-q` | Search by name | |
| `--page` | | Page number | 1 |
| `--per-page` | | Certificates per page | 50 |

### Examples

```bash
# List all certificates
mysigner certificates

# Filter by type
mysigner certificates --type DISTRIBUTION

# Find expired certificates
mysigner certificates --status EXPIRED
```

### Example Output

```bash
$ mysigner certificates

🔐 Signing Certificates

  ✓ Apple Distribution: John Doe (ABC123XYZ)
    ID: 1 | Type: DISTRIBUTION
    Serial: 7C8D9E0F...
    Status: ACTIVE
    Expires: 2027-03-15

  ✓ Apple Development: John Doe (ABC123XYZ)
    ID: 2 | Type: DEVELOPMENT
    Serial: 1A2B3C4D...
    Status: ACTIVE
    Expires: 2027-03-15

  ✗ Apple Distribution: Old Certificate (DEF456)
    ID: 3 | Type: DISTRIBUTION
    Serial: AABBCC...
    Status: EXPIRED
    Expires: 2024-12-01

Page 1 of 1 (3 total)
```

---

## certificate check

Check certificates installed in your Mac's local Keychain.

### Usage

```bash
mysigner certificate check
```

### What It Does

Scans your local Keychain Access for code signing certificates and shows:
- Valid certificates
- Certificates expiring soon
- Expired certificates

### Example Output

```bash
$ mysigner certificate check

🔍 Checking local certificates...

✓ Valid Certificates (2)

  Apple Distribution: John Doe (ABC123XYZ)
    Type: Distribution
    Team: ABC123XYZ
    Expires: 2027-03-15 (425 days)

  Apple Development: John Doe (ABC123XYZ)
    Type: Development
    Team: ABC123XYZ
    Expires: 2027-03-15 (425 days)

────────────────────────────────────────────────────────────────────────────────
Total: 2 certificates installed locally
Status: ✓ All certificates valid

💡 Tip: These are certificates INSTALLED ON YOUR MAC.
    To see all certificates in My Signer API, run: mysigner certificates
```

### No Certificates Found?

If no certificates are found locally:

1. **Sign into Xcode**
   - Open Xcode → Settings → Accounts
   - Sign in with your Apple ID
   - Click "Manage Certificates" or "Download Manual Profiles"

2. **Download from Apple Developer Portal**
   - Go to https://developer.apple.com/account/resources/certificates/list
   - Download your certificate
   - Double-click the .cer file to install

3. **Download from MySigner**
   ```bash
   mysigner certificates
   mysigner certificate download 1
   # Then double-click the .cer file
   ```

---

## certificate download

Download a certificate from MySigner.

### Usage

```bash
mysigner certificate download ID [options]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `ID` | Certificate ID (from `mysigner certificates` list) | Yes |

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--output` | `-o` | Output file path | Certificate name.cer |

### Example

```bash
$ mysigner certificate download 1

🔐 Downloading certificate...

Fetching certificate content...

✓ Certificate downloaded successfully!

Details:
  Name:      Apple Distribution: John Doe (ABC123XYZ)
  Type:      DISTRIBUTION
  Serial:    7C8D9E0F...
  Status:    ACTIVE
  File:      Apple_Distribution_John_Doe.cer

File size: 1247 bytes
```

### Installing Downloaded Certificates

After downloading:
```bash
# Double-click to install in Keychain
open Apple_Distribution_John_Doe.cer
```

> **Note:** You also need the private key that was used to create the certificate. If you don't have the private key, you'll need to create a new certificate.

---

## Creating New Certificates

If you need a new certificate:

### Via `mysigner doctor`

The doctor command can guide you through creating a new certificate:

```bash
mysigner doctor
# Will prompt if you're missing certificates
```

### Manual Process

1. **Generate a CSR (Certificate Signing Request)**
   - Open Keychain Access
   - Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority
   - Enter your email, select "Saved to disk"

2. **Create Certificate in Apple Developer Portal**
   - Go to https://developer.apple.com/account/resources/certificates/add
   - Select "Apple Distribution" or "Apple Development"
   - Upload your CSR
   - Download the .cer file

3. **Install the Certificate**
   - Double-click the .cer file
   - It will pair with the private key in your Keychain

4. **Sync MySigner**
   ```bash
   mysigner sync ios
   ```

---

## Certificate Issues

### "No Signing Identity Found"

This means Xcode can't find a valid certificate in your Keychain.

**Fix:**
1. Check what's in your Keychain:
   ```bash
   mysigner certificate check
   ```

2. If empty, sign into Xcode:
   - Xcode → Settings → Accounts → Your Team → Manage Certificates

3. Or download from MySigner:
   ```bash
   mysigner certificates
   mysigner certificate download 1
   ```

### "Certificate is not yet valid" or "Certificate has expired"

The certificate dates don't match the current date.

**Fix:**
1. Check your system clock is correct
2. If expired, create a new certificate
3. Revoke old certificates in Apple Developer Portal

### "Missing Private Key"

You have the certificate but not the private key.

**Fix:**
1. Find the machine where the certificate was originally created
2. Export the certificate with private key (.p12 file)
3. Import on your machine

Or create a new certificate (this is often easier).

---

## Related Commands

- [`profiles`](profiles) - Manage provisioning profiles
- [`doctor`](doctor) - Diagnose and fix signing issues
- [`signing`](signing) - Configure code signing
- [`sync`](sync) - Sync from App Store Connect
