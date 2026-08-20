---
title: Android Keystore Management for Indie Developers (Without the Horror Stories)
description: A practical guide to creating, storing, rotating, and not losing Android signing keystores. Tooling options included.
order: 6
---

# Android Keystore Management for Indie Developers

**Quick answer:** Generate one upload keystore per app, store it encrypted somewhere you trust, back it up in two physical places. Lose it and you can recover via Google Play App Signing if it was enabled, otherwise your app is unshippable forever. Detailed steps below.

There's a recurring horror story in the Android indie community: developer ships their first app, it gets a few thousand users, their laptop gets stolen with the keystore on it (no backups), they can't ship updates. The user base dies because the new app under a different keystore can't be installed as an update.

This guide covers how to never be that person.

---

## The Two Keys You're Dealing With

In Android shipping there are two distinct signing identities:

1. **Upload key**: what you sign your AAB or APK with before uploading to Play Console.
2. **App signing key**: what Google Play uses to sign the binary that's actually shipped to user devices.

If you enrolled in **Play App Signing** (the default for apps published after August 2021), Google Play manages the app signing key, and you only need to safely manage the upload key. Losing the upload key is annoying but recoverable (Google can reset it after identity verification).

If you opted out of Play App Signing, you're managing both keys yourself. Lose either and your app is permanently unshippable. Don't opt out unless you have a specific reason.

For the rest of this article, "keystore" means upload keystore unless otherwise specified.

---

## Creating a Keystore (Once Per App)

The standard way, via `keytool`:

```bash
keytool -genkey -v \
  -keystore release.keystore \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias release
```

You'll be asked for a keystore password, a key password, and identity info (name, organizational unit, etc). Identity info is shown in the keystore metadata; use real values for serious apps (Google can verify ownership later).

10,000 days (~27 years) is the typical validity. Don't pick a short one; expired keystores are unrecoverable.

Where to store:

- **Local development**: encrypted in your password manager (1Password, Bitwarden) OR encrypted at-rest in a tool like MySigner OR in `~/.android/` with the file mode set to 0600.
- **Never commit to git.** Add the keystore filename to `.gitignore`.
- **Never check in passwords either.** Use environment variables or a secrets manager.

---

## Signing Your Build (Gradle)

In `app/build.gradle.kts`:

```kotlin
android {
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("MYSIGNER_STORE_FILE") ?: "../keystores/release.keystore")
            storePassword = System.getenv("MYSIGNER_STORE_PASSWORD")
            keyAlias = System.getenv("MYSIGNER_KEY_ALIAS") ?: "release"
            keyPassword = System.getenv("MYSIGNER_KEY_PASSWORD")
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

Then build:

```bash
./gradlew bundleRelease
```

Output is `app/build/outputs/bundle/release/app-release.aab`, ready to upload to Play Console.

If you're getting `Keystore was tampered with, or password was incorrect`, your password environment variable is unset or wrong.

---

## Backing Up the Keystore (Do This Today)

Three rules:

1. **Two locations minimum.** One online (encrypted cloud storage), one offline (encrypted USB drive in a drawer).
2. **The keystore file AND the passwords.** Both are needed. People remember the file and forget the password.
3. **Test recovery once a year.** Try unlocking the keystore on a different machine. If it works, you're safe. If it doesn't, you have a problem you discovered before the laptop died.

Acceptable backup setups for indies:

- 1Password vault with the keystore file attached, plus passwords stored as fields, plus the vault shared with one trusted person.
- Encrypted USB drive in your home, plus a copy in a relative's safe.
- A managed tool like MySigner that stores the keystore encrypted at rest on its servers (AES-256), plus your local copy.

Bad backup setups:

- Dropbox folder, unencrypted. Anyone with your Dropbox login can ship your app.
- Email to yourself. Same problem plus email is also easy to phish.
- Single git repo, unencrypted. Anyone who clones can ship.

---

## Losing a Keystore: What Happens

### If Play App Signing is enabled (default since Aug 2021)

You request an upload key reset via Play Console. Google verifies your identity (proof of business, App Signing key fingerprint from the registered Play account, etc.). They issue a new upload key registration. Your users keep getting updates because Google still has the app signing key.

This process takes days to weeks. Expect to lose release velocity in the meantime.

### If Play App Signing is not enabled

Your app cannot be updated. New installs under a different signing identity won't be treated as the "same app," so existing users have to uninstall and reinstall, losing their data.

For practical purposes, the app is dead. You'd typically publish a new app under a new bundle ID and tell users to switch.

This is the horror story.

---

## Rotating a Keystore

If you suspect a keystore was leaked, you should rotate the upload key (the app signing key still lives at Google, untouched).

Steps:

1. Generate a new keystore with `keytool` (different alias from old one).
2. In Play Console → Setup → App integrity → Upload key, click **Request upload key reset**.
3. Google verifies; new upload key is registered.
4. Update your CI / local builds to use the new keystore.

This is one of the few times Play App Signing being mandatory works in your favor. Pre-2021 apps without Play App Signing can't rotate keys.

---

## CI Considerations

Storing the keystore in CI secrets:

```bash
# Base64 encode the keystore once
base64 -i release.keystore > release.keystore.base64
```

Paste the base64 contents into a CI secret (e.g., GitHub Actions `KEYSTORE_BASE64`).

In your CI pipeline:

```yaml
- name: Decode keystore
  run: |
    echo "$KEYSTORE_BASE64" | base64 --decode > release.keystore
  env:
    KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}

- name: Build release AAB
  run: ./gradlew bundleRelease
  env:
    MYSIGNER_STORE_FILE: ${{ github.workspace }}/release.keystore
    MYSIGNER_STORE_PASSWORD: ${{ secrets.STORE_PASSWORD }}
    MYSIGNER_KEY_ALIAS: release
    MYSIGNER_KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
```

The keystore exists only during the CI run and is gone when the runner shuts down.

---

## Using MySigner for Keystore Management

If you'd rather not roll your own backup-and-CI scheme, MySigner handles it:

- Upload your keystore once via the dashboard or `mysigner keystore upload release.keystore`. It's encrypted at rest with AES-256.
- `mysigner ship internal --platform android` (or any track) fetches the keystore, signs, uploads, and submits. No CI secrets to manage.
- Multiple keystores per organization (e.g., one per app). Activate the right one with `mysigner keystore activate <id>`.
- Fingerprint check on upload prevents accidental double-uploads of the same keystore.

The keystore is uploaded to MySigner and encrypted at rest with AWS-KMS envelope encryption (a unique per-credential AES-256-GCM data key); it is decrypted server-side only at signing time and is never stored in plaintext.

Free tier includes Android keystore storage; Pro and Team raise the app and seat limits.

---

## Common Mistakes

### Generating one keystore for many apps

Don't. One keystore per app. If one app's keystore is leaked, the blast radius should be that one app.

### Setting a short validity

10,000 days is fine. Some guides suggest 25 years, which is the same number. Don't generate a 5-year keystore "to be safe" because when it expires, you can't ship.

### Storing the password in the same file as the keystore

The keystore file is encrypted by the keystore password. If you store both in the same place, the encryption is decoration. Separate them.

### Ignoring the Play App Signing prompt

When you first publish, Play Console asks if you want to enroll in Play App Signing. Say yes. It's the recoverability insurance.

### Not testing your backup

If you've never tried to use your backup keystore on a different machine, you don't actually have a backup.

---

## TL;DR

One upload keystore per app, 10,000-day validity, two encrypted backups in two different places. Enroll in Play App Signing. Test recovery once a year. Use a managed tool like MySigner if you'd rather not manage all of this yourself.

[Start free → mysigner.dev](https://mysigner.dev/users/sign_up)
