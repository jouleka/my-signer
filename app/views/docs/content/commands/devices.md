---
title: devices
description: Register and manage test devices for development builds
order: 7
---

# devices

Register and manage test devices (UDIDs) for development and ad-hoc builds.

## Why Register Devices?

To install development or ad-hoc builds on physical iOS devices, you must:
1. Register the device's UDID with Apple
2. Include the device in your provisioning profile

This is required by Apple for all non-App Store distributions.

## Commands Overview

| Command | Description |
|---------|-------------|
| `mysigner devices` | List all registered devices |
| `mysigner device detect` | Auto-detect connected devices |
| `mysigner device add` | Register a new device |
| `mysigner device update` | Rename an existing device |

---

## devices

List all registered test devices.

### Usage

```bash
mysigner devices [options]
```

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--platform` | `-p` | Filter by platform: IOS, MAC_OS, TV_OS | All |
| `--status` | `-s` | Filter by status: ENABLED, DISABLED | All |
| `--search` | `-q` | Search by name or UDID | |
| `--page` | | Page number | 1 |
| `--per-page` | | Devices per page | 50 |

### Example

```bash
$ mysigner devices

📱 Devices

  ✓ John's iPhone 15 Pro (ID: 1)
    UDID: 00008030-001A1B2C3D4E567F
    Platform: IOS | Class: IPHONE
    Status: ENABLED

  ✓ Test iPad (ID: 2)
    UDID: da83bb40dba39e35d258988d856508798db7afba
    Platform: IOS | Class: IPAD
    Status: ENABLED

Page 1 of 1 (2 total)
```

---

## device detect

Auto-detect iOS devices connected to your Mac via USB.

### Usage

```bash
mysigner device detect
```

### What It Does

1. Scans for connected iOS devices
2. Shows device names and UDIDs
3. Offers to register them interactively

### Example

```bash
$ mysigner device detect

🔍 Detecting connected iOS devices...

Found 2 device(s):

  1. John's iPhone
     UDID: 00008030-001A1B2C3D4E567F

  2. Test iPad
     UDID: da83bb40dba39e35d258988d856508798db7afba

Would you like to register a device? (Enter number, or 'n' to skip)
> 1

Enter a name for this device (or press Enter to use 'John's iPhone'):
> John's iPhone 15 Pro

📱 Registering 'John's iPhone 15 Pro'...

✓ Device registered successfully!
  Name:     John's iPhone 15 Pro
  UDID:     00008030-001A1B2C3D4E567F
  Platform: IOS
```

### Tips for Detection

If no devices are detected:
- Make sure the device is connected via USB
- Unlock the device
- Trust the computer on the device when prompted
- For better detection, install libimobiledevice: `brew install libimobiledevice`

---

## device add

Manually register a device by name and UDID.

### Usage

```bash
mysigner device add NAME UDID [options]
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `NAME` | Display name for the device | Yes |
| `UDID` | Device UDID (40 hex chars or 25 chars for newer devices) | Yes |

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--platform` | `-p` | Platform: IOS, MAC_OS, TV_OS | IOS |

### Examples

```bash
# Register an iPhone
mysigner device add "My iPhone 15" 00008030-001A1B2C3D4E567F

# Register an iPad
mysigner device add "Test iPad" da83bb40dba39e35d258988d856508798db7afba

# Register a Mac for Mac Catalyst apps
mysigner device add "MacBook Pro" ABC123DEF456... --platform MAC_OS
```

### Example Output

```bash
$ mysigner device add "My iPhone 15" 00008030-001A1B2C3D4E567F

📱 Registering device...

✓ Device registered successfully!

Details:
  Name:     My iPhone 15
  UDID:     00008030-001A1B2C3D4E567F
  Platform: IOS
  Status:   ENABLED
```

---

## device update

Rename an existing device.

### Usage

```bash
mysigner device update ID NEW_NAME
```

### Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `ID` | Device ID (from `mysigner devices` list) | Yes |
| `NEW_NAME` | New display name | Yes |

### Example

```bash
$ mysigner device update 1 "John's iPhone 15 Pro"

📱 Updating device...

Current name: John's iPhone
New name:     John's iPhone 15 Pro

✓ Device updated successfully!

Details:
  Name:     John's iPhone 15 Pro
  UDID:     00008030-001A1B2C3D4E567F
  Platform: IOS
```

---

## How to Get a Device UDID

### Method 1: Auto-detect (Recommended)

```bash
mysigner device detect
```

Connect your device via USB and run this command. It will find all connected devices and show their UDIDs.

### Method 2: Via Finder (macOS)

1. Connect your iPhone/iPad to your Mac
2. Open **Finder** and select your device in the sidebar
3. Click on the device info (below the device name) to cycle through info
4. When UDID is shown, right-click → **Copy UDID**

### Method 3: Via Xcode

1. Connect your device
2. Open **Xcode → Window → Devices and Simulators**
3. Select your device
4. The UDID is shown as "Identifier"

---

## UDID Formats

| Device Type | UDID Format |
|-------------|-------------|
| iPhone/iPad (older) | 40 hexadecimal characters |
| iPhone/iPad (newer) | 25 characters with dashes (00008030-...) |
| Mac | Various formats |

---

## Limits

- You can register up to **100 devices per year** per Apple Developer account
- Devices count toward the limit even if disabled
- The count resets on your annual membership renewal date

---

## After Registering

After registering new devices, you may need to:

1. **Regenerate provisioning profiles** to include the new device
2. **Run `mysigner sync ios`** to update your local cache
3. **Rebuild your app** with the updated profile

For development builds:
```bash
mysigner build --type development
```

---

## Related Commands

- [`profiles`](profiles) - Manage provisioning profiles
- [`doctor`](doctor) - Check setup and auto-fix issues
- [`sync`](sync) - Sync resources from Apple
