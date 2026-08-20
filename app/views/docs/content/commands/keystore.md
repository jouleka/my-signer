---
title: keystore
description: Manage Android keystores for signing
order: 16
---

# keystore

Upload, download, and manage Android keystores for signing your apps.

## What Is a Keystore?

A keystore (`.jks` or `.keystore` file) contains the private key used to sign your Android app. The same keystore must be used for all updates to your app - if you lose it, you cannot update your app on Google Play.

> **Important:** Back up your keystore securely! If you lose it, you lose the ability to update your app.

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner keystore list` | List all keystores |
| `mysigner keystore upload PATH` | Upload a keystore |
| `mysigner keystore download ID` | Download a keystore |
| `mysigner keystore delete ID` | Delete a keystore |
| `mysigner keystore activate ID` | Set default keystore |

---

## keystore list

List all keystores in your organization.

### Usage

```bash
mysigner keystore list [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--app-id` | Filter by Android app ID |

### Example

```bash
$ mysigner keystore list

🔐 Android Keystores

  ✓ Production Key (ID: 1)
    Key Alias: upload-key
    App: com.company.myapp
    Active: Yes

  ○ Debug Key (ID: 2)
    Key Alias: debug-key
    Active: No

Total: 2 keystore(s)
```

---

## keystore upload

Upload a keystore to MySigner for secure storage and team sharing.

### Usage

```bash
mysigner keystore upload PATH [options]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `PATH` | Path to .jks or .keystore file | Yes |

### Options

| Option | Description |
|--------|-------------|
| `--name` | Name for the keystore |
| `--alias` | Key alias in the keystore |
| `--app-id` | Associate with Android app ID |

### What You'll Be Prompted For

1. **Keystore name** - A friendly name (e.g., "Production Key")
2. **Key alias** - The alias for the signing key inside the keystore
3. **Keystore password** - Password to unlock the keystore
4. **Key password** - Password for the key (often same as keystore password)

### Example

```bash
$ mysigner keystore upload ~/keys/release.jks

🔐 Uploading keystore...

Keystore name (e.g., 'Release Key'): Production Key
Key alias: upload-key
Keystore password: ****
Key password (press Enter if same as keystore): ****

✓ Keystore uploaded successfully!

Details:
  ID:        1
  Name:      Production Key
  Key Alias: upload-key
  Active:    true
```

### Verify Before Upload

You can verify your keystore is valid before uploading:

```bash
keytool -list -keystore ~/keys/release.jks
# Enter password when prompted
# Should show your key alias
```

---

## keystore download

Download a keystore from MySigner.

### Usage

```bash
mysigner keystore download ID [options]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `ID` | Keystore ID (from `keystore list`) | Yes |

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--output` | `-o` | Output path | ~/.mysigner/keystores/ |

### Example

```bash
$ mysigner keystore download 1

🔐 Downloading keystore...

✓ Keystore downloaded!

Details:
  Name:      Production Key
  Key Alias: upload-key
  Path:      ~/.mysigner/keystores/production_key.jks

⚠️ Keep this file secure and backed up!
```

---

## keystore delete

Delete a keystore from MySigner.

### Usage

```bash
mysigner keystore delete ID
```

> **Warning:** This cannot be undone. Make sure you have a backup!

### Example

```bash
$ mysigner keystore delete 2

⚠️ You are about to delete:
  Name: Debug Key
  Key Alias: debug-key

Are you sure? This cannot be undone. (y/n) y

✓ Keystore deleted
```

---

## keystore activate

Set a keystore as the active/default one for signing.

### Usage

```bash
mysigner keystore activate ID
```

### Example

```bash
$ mysigner keystore activate 1

🔐 Activating keystore...

✓ Keystore activated!

Production Key is now the default keystore
```

When you run `mysigner ship internal`, it will automatically use the active keystore.

---

## Keystore Security

### Stored Encrypted

Keystores are stored encrypted on MySigner servers:
- Encrypted at rest
- Only your organization can access them
- Credentials (passwords) are encrypted separately

### Local Storage

Downloaded keystores are stored in:
```
~/.mysigner/keystores/
```

Protect this directory:
```bash
chmod 700 ~/.mysigner/keystores
```

### Best Practices

1. **Back up your keystore** in multiple secure locations
2. **Use strong passwords** for both keystore and key
3. **Never commit keystores** to version control
4. **Limit who has access** to the keystore
5. **Consider Google Play App Signing** for additional protection

---

## Creating a New Keystore

If you need to create a new keystore:

```bash
keytool -genkeypair -v \
  -keystore release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload-key \
  -storepass your-store-password \
  -keypass your-key-password
```

You'll be prompted for:
- Your name
- Organization
- City, State, Country

Then upload to MySigner:
```bash
mysigner keystore upload release.jks
```

---

## Troubleshooting

### "Invalid Keystore" Error

```
Error: Upload failed: keystore was tampered with or password is incorrect
```

**Fix:** Verify the keystore and password:
```bash
keytool -list -keystore your.jks
# Enter password
```

### "Key Alias Not Found"

The key alias you specified doesn't exist in the keystore.

**Fix:** List the aliases in your keystore:
```bash
keytool -list -keystore your.jks
# Look for "Alias name:" in output
```

### No Active Keystore

When running `mysigner ship`, you might see:
```
No active keystore found
```

**Fix:**
```bash
# List keystores
mysigner keystore list

# Activate one
mysigner keystore activate 1
```

---

## Related Commands

- [`android`](android) - Register apps and build AAB files
- [`ship`](ship) - Build and upload to Google Play
- [`doctor`](doctor) - Diagnose setup issues
