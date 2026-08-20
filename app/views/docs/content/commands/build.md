---
title: build
description: Build an Xcode archive (.xcarchive)
order: 3
---

# build

Build an Xcode archive (.xcarchive) without exporting or uploading. This is an advanced command — **most users should use [`mysigner ship`](ship)** which handles everything automatically.

## Usage

```bash
mysigner build [options]
```

### Alias

```bash
mysigner b [options]
```

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--configuration` | `-c` | Build configuration | `Release` |
| `--target` | `-t` | Target to build | Auto-detected |
| `--scheme` | `-s` | Scheme to build | Target name |
| `--type` | | Build type: development, adhoc, appstore, enterprise | `appstore` |
| `--team` | | Development team ID | From project |
| `--bundle-id` | `-b` | Bundle ID override | From project |
| `--skip-extensions` | | Skip extension targets | `false` |

### What It Does

1. Detects your project and identifies the framework (Native iOS, React Native, Flutter, Ionic/Capacitor, Expo)
2. Runs framework-specific pre-build steps if needed (`expo prebuild`, `cap sync`, `flutter pub get`, etc.)
3. Validates signing configuration
4. Runs `xcodebuild archive` to create an .xcarchive

### Examples

```bash
# Auto-detect and build
mysigner build

# Specify scheme and configuration
mysigner build --scheme MyApp --configuration AppStore

# Override bundle ID (useful for white-labeling)
mysigner build --bundle-id com.client.app

# Skip extensions that aren't configured
mysigner build --skip-extensions
```

### Example Output

```bash
$ mysigner build

🔍 Detecting project...

✓ Found: MyApp.xcworkspace (Native iOS)

🎯 Target: MyApp
📦 Bundle ID: com.company.myapp
⚙️ Configuration: Release
🔐 Signing: Automatic

🔍 Validating signing setup...
✓ Signing configuration valid

Building archive...
▸ Compiling MyApp.swift
▸ Compiling AppDelegate.swift
...

================================================================================
✓ Build succeeded!
================================================================================

📦 Archive: ~/Library/Developer/Xcode/Archives/2026-01-23/MyApp.xcarchive

Next steps:
  mysigner export ~/Library/Developer/Xcode/Archives/2026-01-23/MyApp.xcarchive
  mysigner ship testflight
```

---

## When to Use Build

### Use `mysigner ship` when:
- You want the simplest workflow
- Building from source and uploading in one step
- Standard release workflow

### Use `mysigner build` when:
- You only need an archive, not an IPA
- Testing the build process
- Creating archives for later export

---

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error |

## Related Commands

- [`ship`](ship) - All-in-one build, sign, and upload
- [`export`](export) - Export archive to IPA
- [`upload`](upload) - Upload IPA to TestFlight
- [`submit`](submit) - Submit for App Store review
- [`doctor`](doctor) - Diagnose build issues
