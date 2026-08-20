---
title: Troubleshooting
description: Solutions for common issues and errors
order: 9
---

# Troubleshooting

Solutions for common issues you might run into while using MySigner. If you're in a hurry, start with the quick fixes below — they resolve most problems.

---

## Quick Fixes

Most issues can be resolved with one of these commands:

| What to try | Command |
|-------------|---------|
| Auto-diagnose and fix | `mysigner doctor` |
| Force refresh from Apple/Google | `mysigner sync --force` |
| Check your setup | `mysigner status` |
| Get detailed error output | `DEBUG=1 mysigner ship testflight` |

> **Tip:** Run `mysigner doctor` first. It checks your entire environment and can auto-fix most common problems, including missing profiles, credentials, and signing identities.

---

## Authentication Issues

Problems logging in, connecting to the API, or switching organizations.

### "Not authenticated" or "Invalid token"

> `Error: Not authenticated. Please run 'mysigner login' first.`

Your API token is missing, expired, or invalid. Re-authenticate:

```bash
mysigner login
```

If that doesn't work, start fresh with the onboarding wizard:

```bash
mysigner onboard
```

### "Organization not found"

> `Error: Organization not found or you don't have access.`

You're trying to access an organization your token doesn't belong to. Check which organizations you have access to and switch:

```bash
mysigner orgs
mysigner switch
```

### "API rate limit exceeded"

> `Error: Rate limit exceeded. Please wait before retrying.`

Too many requests to App Store Connect or Google Play in a short period.

- Wait 1-2 minutes, then retry
- In CI/CD pipelines, add delays between consecutive builds
- Contact support if the issue persists

---

## iOS Signing Issues

Problems with certificates, provisioning profiles, and code signing identity.

### "No signing identity for team"

> `Error: No signing identity for team 'ABC123XYZ'`

Your Mac doesn't have the distribution certificate installed in its Keychain. Either download it through Xcode:

1. Open **Xcode** → **Settings** → **Accounts**
2. Select your team
3. Click **Download Manual Profiles**

Or let MySigner diagnose and guide you:

```bash
mysigner doctor
```

### "Profile doesn't include signing certificate"

> `Error: Provisioning profile doesn't include signing certificate`

The provisioning profile was created with a different certificate than the one on your Mac. Refresh your data and let doctor create a new profile:

```bash
mysigner sync --force
mysigner doctor
```

### "Bundle ID not registered"

> `Error: Bundle identifier 'com.company.myapp' is not registered`

Your app's bundle identifier isn't registered in App Store Connect yet. Register it and sync:

```bash
mysigner bundleid register com.company.myapp
mysigner sync
```

### "Provisioning profile expired"

> `Error: Provisioning profile has expired`

Provisioning profiles expire annually. Force a sync to get fresh ones, or run doctor to auto-create replacements:

```bash
mysigner sync --force
```

```bash
mysigner doctor
```

### "Certificate revoked or expired"

> `Error: Certificate has been revoked`

Your distribution certificate is no longer valid. To fix this:

1. Check certificate status in the MySigner dashboard
2. If revoked, create a new certificate in the [Apple Developer Portal](https://developer.apple.com/)
3. Download and install the new certificate on your Mac
4. Run `mysigner sync --force` to update profiles

---

## iOS Build Issues

Problems during the Xcode build, archive, or export process.

### "No scheme found"

> `Error: No scheme found matching 'MyApp'`

Xcode can't find the build scheme. List your available schemes and specify the correct one:

```bash
xcodebuild -list
mysigner ship testflight --scheme "CorrectSchemeName"
```

If the scheme exists but isn't visible, make it shared in Xcode:

1. **Product** → **Scheme** → **Manage Schemes**
2. Check the **Shared** checkbox for your scheme
3. Commit the resulting `.xcscheme` file

### "Archive failed"

> `Error: xcodebuild failed with exit code 65`

The Xcode build itself is failing. To get more detail:

1. Try building in Xcode directly to see the full error log
2. Check for code errors, missing dependencies, or outdated pods
3. Run with verbose output for more context:

```bash
DEBUG=1 mysigner build --verbose
```

### "Export failed"

> `Error: Failed to export archive`

The archive built successfully but exporting to IPA failed. This is usually a signing configuration issue.

Run `mysigner doctor` to check your signing setup, or try exporting manually in Xcode to see the specific error.

Common causes:
- Wrong provisioning profile type (Development vs Distribution)
- Entitlements mismatch between app and profile
- Capabilities enabled in the app but not in the profile

### "No devices in provisioning profile"

> `Error: Profile contains no devices`

Development profiles require at least one registered device. Register your device and refresh:

```bash
mysigner device add "My iPhone" YOUR_UDID
mysigner sync --force
```

> **Tip:** Don't know your device UDID? Run `mysigner device detect` with your device connected to auto-detect it.

---

## iOS Upload Issues

Problems uploading builds to App Store Connect or TestFlight.

### "App Store Connect credentials not configured"

> `Error: App Store Connect credentials not configured`

No App Store Connect API key has been set up. You can configure it through:

1. The MySigner dashboard → **App Store Connect** section
2. Or run `mysigner doctor` — it will detect the missing credentials and walk you through setup interactively

### "Upload validation failed"

> `Error: Asset validation failed`

Apple rejected the build during upload validation. Check the specific error in the output:

| Error | Solution |
|-------|----------|
| Missing icon sizes | Add all required app icon sizes to your asset catalog |
| Invalid bundle version | Increment `CFBundleVersion` — it must be higher than the last upload |
| Privacy description missing | Add required `NS*UsageDescription` keys to `Info.plist` |
| Entitlements mismatch | Verify app entitlements match provisioning profile capabilities |

### "Build already exists"

> `Error: Version 1.0 (42) already exists`

A build with this exact version and build number has already been uploaded. Either increment the build number manually in Xcode, or let MySigner handle it — `mysigner ship testflight` auto-increments for you.

### "Upload timeout"

> `Error: Upload timed out after 10 minutes`

The upload is taking too long, usually due to a large app or slow connection.

- Check your internet connection
- Reduce app size (strip debug symbols, compress assets)
- In CI/CD, increase the job timeout settings

---

## Android Issues

Problems with Android builds, keystores, and Google Play uploads.

### "Package name not found"

> `Error: Package 'com.company.myapp' not found`

The package name isn't registered in Google Play Console.

1. Verify the app exists in [Google Play Console](https://play.google.com/console/)
2. Check that the package name matches what's in your `build.gradle`
3. Confirm the service account has been granted access to the app

### "Version code already exists"

> `Error: Version code 42 has already been used`

You're trying to upload a build with a version code that's already been used. MySigner auto-increments version codes by default, so simply running the command again should work. If you prefer to manage it manually, bump `versionCode` in your `build.gradle`.

### "Keystore not found" or "Keystore password incorrect"

> `Error: Failed to sign APK/AAB`

There's a problem with your signing keystore. Check the MySigner dashboard:

1. Go to **Keystores** and verify one is uploaded and activated
2. Double-check the keystore password, alias, and key password
3. Re-upload the keystore if credentials have changed

### "Google Play credentials invalid"

> `Error: The caller does not have permission`

The Google Play service account doesn't have the right permissions.

1. Open [Google Play Console](https://play.google.com/console/) → **Users and permissions**
2. Verify the service account email is listed with **Release Manager** access
3. Ensure the **Google Play Android Developer API** is enabled in [Google Cloud Console](https://console.cloud.google.com/)
4. Re-upload the service account JSON in MySigner if needed

### "Gradle build failed"

> `Error: Gradle build failed with exit code 1`

The Android build itself is failing. Try isolating the issue:

```bash
# Clean and rebuild directly
cd android && ./gradlew clean && ./gradlew assembleRelease
```

If that works but MySigner fails, run with verbose output:

```bash
mysigner ship internal --platform android --verbose
```

### "AAB not accepted"

> `Error: APK format is deprecated for new apps`

Google Play requires AAB (Android App Bundle) for new apps. MySigner builds AAB by default — no extra configuration needed:

```bash
mysigner ship internal --platform android
```

> **Note:** If you have an older project still configured for APK, update your `build.gradle` to produce AAB bundles.

---

## CI/CD Issues

Problems running MySigner in continuous integration pipelines.

### "Runner not available" (GitHub Actions)

> `Error: No runners matched the specified labels`

No matching runner is available for your job.

- Use `runs-on: macos-latest` for iOS builds (requires macOS for Xcode)
- Use `runs-on: ubuntu-latest` for Android-only builds
- For self-hosted runners, verify they're online and properly labeled

### "Not authenticated in CI/CD"

> `Error: Not authenticated. Please run 'mysigner login' first.`

The CLI isn't configured on the CI runner. Set the required environment variables in your CI pipeline:

```yaml
env:
  MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
  MYSIGNER_ORG_ID: ${{ secrets.MYSIGNER_ORG_ID }}
```

The CLI automatically detects these environment variables — no config file needed.

See the [GitHub Actions guide](/docs/guides/ci-cd-github) for complete workflow examples.

### Build times out

> `Error: The job exceeded the maximum time limit`

The CI job is hitting its time limit. To fix:

- **GitHub Actions:** Increase `timeout-minutes` in your workflow (default is 360)
- **GitLab CI:** Increase `timeout` in your job configuration
- **General:** Add dependency caching to speed up builds significantly

### Caching not working

Builds aren't using cached dependencies, making them slower than expected.

- Verify the cache key includes a hash of your lockfile (`Podfile.lock`, `package-lock.json`, etc.)
- Double-check the cache paths match where dependencies are actually installed
- Run with debug output to confirm whether caches are hitting or missing

---

## General Issues

Environment and installation problems.

### "Command not found: mysigner"

The CLI isn't installed or isn't in your shell's PATH.

```bash
gem install mysigner
```

If you're using rbenv, rehash after installing:

```bash
rbenv rehash
```

Verify the installation:

```bash
which mysigner
mysigner version
```

### "Ruby version too old"

> `Error: mysigner requires Ruby version >= 3.2`

MySigner requires **Ruby 3.2 or newer**. Check your version and upgrade if needed:

```bash
ruby -v
rbenv install 3.2.0
rbenv global 3.2.0
```

### "SSL certificate error"

> `Error: SSL_connect returned=1 errno=0 state=error`

SSL/TLS verification is failing, usually due to outdated CA certificates.

On macOS:

```bash
brew install ca-certificates
```

If you're using rbenv, reinstalling Ruby can also resolve this:

```bash
rbenv install 3.2.0
```

### Config file corruption

> `Error: Failed to parse config file`

The configuration file at `~/.mysigner/config.yml` is corrupted or invalid. Reset it and re-authenticate:

```bash
rm ~/.mysigner/config.yml
mysigner onboard
```

---

## Debug Mode

When you need more detail about what's going wrong, MySigner offers two levels of verbosity:

| Level | How to enable | What it shows |
|-------|---------------|---------------|
| Verbose | `--verbose` or `-v` flag | Detailed step-by-step output |
| Full debug | `DEBUG=1` environment variable | Everything, including API calls and stack traces |

```bash
# Verbose output
mysigner ship testflight --verbose

# Full debug mode
DEBUG=1 mysigner ship testflight

# Combine both for maximum detail
DEBUG=1 mysigner doctor --verbose
```

> **Tip:** When reporting issues to support, always include the output from `DEBUG=1` — it contains the information needed to diagnose the problem.

---

## Getting Help

If you're still stuck after trying the above:

1. **Run doctor** — `mysigner doctor` diagnoses and auto-fixes most issues
2. **Check status** — `mysigner status` shows your current configuration
3. **Enable debug** — `DEBUG=1` reveals detailed error information
4. **Search docs** — Use the docs search for specific error messages
5. **Contact support** — Reach out via the MySigner dashboard

> **Avoid most of this list entirely:** turn on the **Sync Failures**, **Revocations**, and expiry notifications in [Notifications](/docs/dashboard/notifications). They give you advance warning before a certificate / profile / keystore expires or a sync starts failing — instead of finding out via a broken CI build at the worst possible moment.

### Collecting Information for Support

When contacting support, include the output of these commands:

```bash
mysigner version
mysigner status
mysigner doctor
```

For build-specific issues, capture the full debug log:

```bash
DEBUG=1 mysigner ship testflight 2>&1 | tee debug.log
```

This creates a `debug.log` file you can share with the support team.

---

## Related

- [Doctor Command](/docs/commands/doctor) — Auto-diagnose and fix common issues
- [Sync Command](/docs/commands/sync) — Refresh data from Apple and Google
- [Notifications](/docs/dashboard/notifications) — Proactive alerts for expiry, sync failures, revocations
- [Getting Started](/docs/quickstart/getting-started) — Initial setup guide
