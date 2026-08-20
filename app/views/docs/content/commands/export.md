---
title: export
description: Export an Xcode archive to IPA
order: 5
---

# export

Export a `.xcarchive` to a signed `.ipa` file.

This is an advanced command for users who want to separate the build and export steps. For most workflows, use [`ship`](ship) which handles everything automatically.

---

## Commands Overview

| Command | Alias | Description |
|---------|-------|-------------|
| `mysigner export ARCHIVE_PATH` | `e` | Export archive to IPA |

---

## export

Export an Xcode archive (`.xcarchive`) to a signed IPA file.

### Usage

```bash
mysigner export ARCHIVE_PATH [options]
```

### Alias

```bash
mysigner e ARCHIVE_PATH [options]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `ARCHIVE_PATH` | Path to the .xcarchive file | Yes |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--method` | Export method: `appstore`, `adhoc`, `enterprise`, `development` | `appstore` |
| `--output` | Output directory for the IPA | Same directory as archive |

### Export Methods

| Method | Description | Use Case |
|--------|-------------|----------|
| `appstore` | App Store / TestFlight distribution | Production releases |
| `adhoc` | Ad-hoc distribution | Testing on registered devices |
| `enterprise` | Enterprise distribution | In-house apps |
| `development` | Development builds | Local testing |

### Examples

```bash
# Export for App Store (default)
mysigner export MyApp.xcarchive

# Export for ad-hoc distribution
mysigner export MyApp.xcarchive --method adhoc

# Export to specific directory
mysigner export MyApp.xcarchive --output ./builds

# Using alias
mysigner e MyApp.xcarchive --method adhoc --output ./builds
```

### Example Output

```bash
$ mysigner export MyApp.xcarchive

📦 My Signer - Export
================================================================================

Exporting archive...
▸ Creating export options
▸ Signing with distribution profile
▸ Creating IPA

================================================================================
✓ Export succeeded!
================================================================================

📦 IPA: ~/Archives/MyApp.ipa

Next steps:
  mysigner upload testflight ~/Archives/MyApp.ipa
  mysigner ship testflight
```

---

## When to Use Export

### Separate Build and Export

If you need to build once and export multiple times:

```bash
# Build archive once
mysigner build

# Export for different purposes
mysigner export MyApp.xcarchive --method appstore --output ./appstore
mysigner export MyApp.xcarchive --method adhoc --output ./adhoc
```

### CI/CD Pipelines

When you want fine-grained control in CI:

```bash
# Build step
mysigner build

# Export step (can be conditional)
if [ "$DEPLOY_TYPE" = "production" ]; then
  mysigner export MyApp.xcarchive --method appstore
else
  mysigner export MyApp.xcarchive --method adhoc
fi
```

### Using Existing Archives

If you have an archive from Xcode:

```bash
mysigner export ~/Library/Developer/Xcode/Archives/2026-01-15/MyApp.xcarchive
```

---

## Troubleshooting

### "No matching provisioning profile"

The export method requires a compatible provisioning profile:

```bash
# Sync profiles first
mysigner sync ios

# Check available profiles
mysigner profiles
```

### "Archive not found"

Ensure the path points to a valid `.xcarchive`:

```bash
# List recent archives
ls -la ~/Library/Developer/Xcode/Archives/
```

---

## Related Commands

- [`build`](build) - Build an Xcode archive
- [`upload`](upload) - Upload IPA to TestFlight
- [`ship`](ship) - Build, export, and upload in one step
