---
title: sync
description: Sync data from App Store Connect and Google Play
order: 21
---

# sync

Sync your organization's data from App Store Connect and/or Google Play.

## Usage

```bash
mysigner sync [PLATFORM] [options]
```

> **Plan note:** `mysigner sync` is always a manual command. Recurring dashboard sync runs on every plan — cadence scales with tier (Free daily, Pro every 6h, Team every 3h for store sync; Free daily, Pro every 2h, Team every 30 min for reviews).

## Platforms

| Platform | Description |
|----------|-------------|
| `ios` (default) | Sync from App Store Connect |
| `android` | Sync from Google Play |
| `all` | Sync from both platforms |

## Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--force` | `-f` | Force sync even if recently synced |

---

## What Gets Synced

### iOS (App Store Connect)

| Resource | Description |
|----------|-------------|
| Apps | Apps registered in App Store Connect |
| Builds | Uploaded builds and their processing status |
| Certificates | Signing certificates |
| Devices | Registered test devices |
| Profiles | Provisioning profiles |
| Bundle IDs | App IDs and capabilities |

### Android (Google Play)

| Resource | Description |
|----------|-------------|
| Apps | Registered Android apps |
| Tracks | Release tracks and their status |
| Builds | Uploaded AABs and version codes |

---

## Examples

### Sync iOS Data

```bash
$ mysigner sync

🔄 Syncing data from App Store Connect...

✓ iOS sync completed!

Last synced: 2026-01-23T10:30:00Z

📊 Summary:
  • Apps: 3
  • Builds: 15
  • Certificates: 2
  • Devices: 5
  • Profiles: 8
```

### Sync iOS Explicitly

```bash
$ mysigner sync ios
```

### Sync Android Data

```bash
$ mysigner sync android

🔄 Syncing data from Google Play...

✓ Android sync started!

Sync runs in the background. Check status with:
  mysigner apps --platform android

💡 Google Play sync may take a few minutes.
   Unlike iOS, Google Play doesn't auto-discover apps.
   If no apps appear, add them in the web dashboard first.
```

### Sync Both Platforms

```bash
$ mysigner sync all

🔄 Syncing data from App Store Connect...
✓ iOS sync completed!

🔄 Syncing data from Google Play...
✓ Android sync started!
```

### Force Sync

Force a sync even if data was recently synced:

```bash
$ mysigner sync ios --force
```

---

## When to Sync

Run sync when:

### After Changes in Apple Developer Portal
- Created new certificates
- Registered new devices
- Created new bundle IDs
- Modified capabilities

### After Changes in App Store Connect
- Created new apps
- Uploaded new builds
- Modified release information

### After Changes in Google Play Console
- Created new apps
- Uploaded new builds
- Changed track configurations

### Before Building
If you haven't synced recently:
```bash
mysigner sync
mysigner ship testflight
```

---

## Background Syncs

### Triggered Syncing

Syncs are typically triggered when:
- You run `mysigner sync`
- You use setup or build flows that explicitly refresh remote state
- A recurring or scheduled sync runs from the dashboard (every plan; cadence varies by tier)

### Manual Syncing

Use manual sync when you need:
- Immediate access to new resources
- To troubleshoot missing data
- To verify resources exist

---

## Sync Status

### iOS Sync

iOS sync is immediate - when it completes, your data is up to date.

### Android Sync

Android sync runs in the background:
1. The `sync android` command starts the job
2. Check progress in the web dashboard
3. Or run `mysigner apps --platform android` to see results

---

## Troubleshooting

### "No active credential"

```bash
$ mysigner sync ios
✗ iOS sync failed: No active App Store Connect credential
```

**Fix:** Configure App Store Connect credentials:
```bash
mysigner doctor
# Follow the setup wizard
```

### "No active Google Play credential"

```bash
$ mysigner sync android
✗ Google Play not configured
```

**Fix:** Configure Google Play credentials in the web dashboard or via:
```bash
mysigner doctor
```

### Sync Seems Slow

Some resources take time to sync:
- Large app catalogs
- Many builds
- Complex team structures

Force a fresh sync:
```bash
mysigner sync ios --force
```

### Missing Resources After Sync

If resources don't appear after syncing:

1. **Check API credentials have proper permissions**
   - iOS: API key needs appropriate role (App Manager or Admin)
   - Android: Service account needs release permissions

2. **Check Team ID is set (iOS)**
   - Team ID is required for filtering resources
   - Set it in the web dashboard if missing

3. **Try force sync**
   ```bash
   mysigner sync --force
   ```

---

## Related Commands

- [`doctor`](doctor) - Diagnose setup issues
- [`status`](auth#status) - Check connection
- [`apps`](android#apps) - List apps from stores
