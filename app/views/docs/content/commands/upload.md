---
title: upload
description: Upload an IPA to TestFlight
order: 6
---

# upload

Upload an existing IPA file to TestFlight.

This is an advanced command for users who have a pre-built IPA. For most workflows, use [`ship`](ship) which handles everything automatically.

---

## Commands Overview

| Command | Alias | Description |
|---------|-------|-------------|
| `mysigner upload testflight IPA_PATH` | `u` | Upload IPA to TestFlight |

---

## upload testflight

Upload an existing IPA file to TestFlight for beta testing.

### Usage

```bash
mysigner upload testflight IPA_PATH [options]
```

### Alias

```bash
mysigner u testflight IPA_PATH [options]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `IPA_PATH` | Path to the .ipa file | Yes |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--wait` | Wait for processing to complete | `false` |

### Examples

```bash
# Upload IPA
mysigner upload testflight MyApp.ipa

# Upload and wait for processing
mysigner upload testflight MyApp.ipa --wait

# Using alias
mysigner u testflight MyApp.ipa --wait
```

### Example Output

```bash
$ mysigner upload testflight MyApp.ipa

☁️  My Signer - Upload to TestFlight
================================================================================

🔐 Fetching App Store Connect credentials...
✓ Credentials loaded

Uploading to App Store Connect...
▸ Validating IPA
▸ Uploading... 45.2 MB / 45.2 MB (100%)
▸ Upload complete

🎉 Upload complete!

Next steps:
  • Open App Store Connect to see your build
  • Wait for processing (5-15 minutes)
  • Distribute to TestFlight testers
```

### With --wait

When you use `--wait`, the CLI polls until Apple finishes processing:

```bash
$ mysigner upload testflight MyApp.ipa --wait

☁️  My Signer - Upload to TestFlight
================================================================================

🔐 Fetching App Store Connect credentials...
✓ Credentials loaded

Uploading to App Store Connect...
▸ Validating IPA
▸ Uploading... 45.2 MB / 45.2 MB (100%)
▸ Upload complete

🎉 Upload complete!

⏳ Waiting for processing...
✓ Build is ready for testing!
```

---

## When to Use Upload

### Uploading Pre-built IPAs

If you have an IPA from another source:

```bash
# From a CI build
mysigner upload testflight ./artifacts/MyApp.ipa

# From Xcode export
mysigner upload testflight ~/Desktop/MyApp.ipa
```

### CI/CD Pipelines

When you want fine-grained control:

```bash
# Build and export in earlier steps
mysigner build
mysigner export MyApp.xcarchive

# Upload in a separate step
mysigner upload testflight MyApp.ipa --wait
```

### Re-uploading Failed Builds

If a previous upload failed after export:

```bash
# Just retry the upload
mysigner upload testflight MyApp.ipa
```

---

## Processing Time

After upload, Apple processes the build before it's available for testing:

| Phase | Typical Duration |
|-------|------------------|
| Upload verification | 1-5 minutes |
| Processing | 5-30 minutes |
| Ready for testing | - |

Use `--wait` to have the CLI wait for processing to complete.

---

## Troubleshooting

### "Invalid IPA"

Ensure the IPA was properly signed:

```bash
# Check IPA contents
unzip -l MyApp.ipa

# Re-export with proper signing
mysigner export MyApp.xcarchive --method appstore
```

### "Version already exists"

You cannot upload the same version and build number twice:

1. Increment your build number in Xcode
2. Re-build and export
3. Upload again

### "App not found"

The bundle ID must match an app in App Store Connect:

```bash
# Check registered bundle IDs
mysigner bundleid list

# Verify app exists
mysigner apps --platform ios
```

---

## Related Commands

- [`export`](export) - Export archive to IPA
- [`build`](build) - Build an Xcode archive
- [`ship`](ship) - Build, export, and upload in one step
- [`submit`](submit) - Submit for App Store review
