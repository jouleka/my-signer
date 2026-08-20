---
title: CLI Commands
description: Complete reference for all MySigner CLI commands
order: 0
---

# CLI Command Reference

The MySigner CLI provides commands for building, signing, and deploying iOS and Android apps. Commands are organized into logical categories.

## Quick Reference

| Command | Description | Alias |
|---------|-------------|-------|
| `mysigner ship TARGET` | Build + sign + upload in one step | `s` |
| `mysigner build` | Build .xcarchive only | `b` |
| `mysigner export ARCHIVE` | Export archive to IPA | `e` |
| `mysigner upload testflight IPA` | Upload IPA to TestFlight | `u` |
| `mysigner submit [TRACK]` | Submit for review | |
| `mysigner validate` | Validate signing config on server | |
| `mysigner doctor` | Run health check | `d` |
| `mysigner status` | Check connection and credentials | `st` |
| `mysigner version` | Show CLI version and system info | |

## Command Categories

### Build & Ship

The core commands for building and deploying your apps:

- **[ship](ship)** - The all-in-one command: build, sign, and upload
- **[build](build)** - Build an Xcode archive (.xcarchive)
- **[export](export)** - Export archive to IPA
- **[upload](upload)** - Upload IPA to TestFlight
- **[submit](submit)** - Submit an existing build for review

### Authentication

Commands for logging in and managing your account:

- **[auth](auth)** - Login, logout, onboard, status, orgs, switch, config

### Diagnostics

Commands for troubleshooting and syncing:

- **[doctor](doctor)** - Health check and auto-fix common issues
- **[sync](sync)** - Sync data from App Store Connect or Google Play

### Validation

Pre-build validation to catch issues early:

- **[validate](validate)** - Check signing configuration on the server before building

### iOS Resources

Commands for managing iOS provisioning resources:

- **[devices](devices)** - List and register test devices
- **[profiles](profiles)** - List and manage provisioning profiles
- **[certificates](certificates)** - List and download signing certificates
- **[bundleid](bundle-ids)** - Register and manage bundle identifiers
- **[merchant-ids](merchant-ids)** - List and manage Apple Pay Merchant IDs
- **[app-groups](app-groups)** - List and manage App Groups
- **[signing](signing)** - Configure code signing in Xcode projects
- **[release](release)** - Manage App Store release configurations

### Android Resources

Commands for managing Android resources:

- **[keystore](keystore)** - Upload, download, and manage Android keystores
- **[android](android)** - Register apps and build AAB files
- **[gp-credential](gp-credential)** - Manage Google Play API credentials
- **[tracks](tracks)** - List and view Google Play tracks

### General

Commands that work across platforms:

- **[apps](apps)** - List apps from App Store Connect and Google Play

## Global Options

All commands support these global options:

| Option | Description |
|--------|-------------|
| `--verbose` / `-v` | Show detailed output |
| `--help` | Show help for command |

## Getting Started

If you're new to MySigner, start with the [Quickstart Guide](/docs/quickstart/getting-started) or run:

```bash
mysigner onboard
```

This interactive wizard will guide you through:
1. Creating an account
2. Setting up your organization
3. Generating an API token
4. Configuring App Store Connect credentials
