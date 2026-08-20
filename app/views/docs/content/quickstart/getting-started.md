---
title: Getting Started
description: Set up MySigner and ship your first build in 5 minutes
order: 1
---

# Getting Started

Go from source code to App Store review or Google Play — in a single command. This guide walks you through installing the CLI, connecting your Apple and Google accounts, and shipping your first build.

> **Works with any mobile framework:** MySigner auto-detects your project type — native Swift/Kotlin, React Native, Flutter, Ionic/Capacitor, Expo, or .NET MAUI. Just run commands from your project root.

---

## Prerequisites

### iOS

- macOS with **Xcode** installed
- An [Apple Developer account](https://developer.apple.com/) with Admin access
- A mobile project that builds to iOS

### Android

- **Java 11+** (JDK) installed
- **Android SDK** installed with `ANDROID_HOME` configured
- A [Google Play Developer account](https://play.google.com/console/)
- A mobile project that builds to Android

### CLI

- **Ruby 3.2+** (check with `ruby -v`)

---

## Step 1: Install the CLI

```bash
gem install mysigner
```

Verify it's working:

```bash
mysigner version
```

> **Tip:** If you use rbenv, run `rbenv rehash` after installing.

---

## Step 2: Set Up Your Account

You'll need three things before connecting the CLI: a MySigner account, an organization, and an API token. If you already have these, skip to [Step 3](#step-3-connect-the-cli).

### Create an account

1. Visit the [MySigner Dashboard](/) and sign up
2. You can use email, Google, GitHub, or Apple to authenticate
3. Verify your email if you signed up with email

> **You're auto-enrolled in a 14-day Pro trial — no card required.** Every new account gets full Pro features (store uploads, AI translate / rewrite, screenshot studio quotas, etc.) for 14 days. After day 14 your account drops to **Free** unless you subscribe — nothing is deleted. See [14-Day Pro Trial](/docs/dashboard/trial) for the full breakdown.

### Create an organization

Organizations hold your apps, credentials, and team members.

1. After signing in, click **New Organization** in the sidebar
2. Enter a name (e.g., "Acme Inc")
3. Click **Create Organization**

> **Plan note:** Organization limits depend on your current plan. Early-access upgrades are still handled manually rather than through self-serve checkout.

### Generate an API token

The CLI uses API tokens to authenticate with your MySigner account.

1. Go to **API Tokens** in the sidebar
2. Click **Create Token**
3. Give it a descriptive name (e.g., "MacBook Pro CLI")
4. Select the **read** and **write** scopes (Admin scope is also available — only Admin / Owner roles can create it; see the [Permissions matrix](/docs/dashboard/permissions))
5. Click **Create** and **copy the token immediately** — you won't be able to see it again

> **Warning:** Keep your API token secret. Never commit it to version control or share it publicly. In CI/CD, store it as an encrypted secret.

---

## Step 3: Connect the CLI

Run the onboarding wizard — it walks you through connecting your CLI to MySigner step by step:

```bash
mysigner onboard
```

The wizard guides you through:

1. **Account setup** — confirms you have a MySigner account (or helps you create one)
2. **Organization setup** — confirms you have an organization ready
3. **API token** — walks you through generating a token if you haven't yet
4. **CLI login** — enter your email and paste the token to authenticate
5. **Store credentials** — optionally configure App Store Connect right away

Your **API token** is stored encrypted at rest in `~/.mysigner/config.yml` using AES-256-GCM:

- **macOS** — the encryption key lives in the system Keychain (`com.mysigner.cli` / `config_encryption_key`). Tokens are never on disk in plaintext.
- **Linux / Windows** — the encryption key falls back to a file at `~/.mysigner/.encryption_key` (mode `0600`, owner-only). This is roughly equivalent in security to the config file itself; for the strongest posture, prefer the env-var path described below in CI/CD.

Other credentials (App Store Connect `.p8` private keys, Google Play service-account JSON, keystore passwords) are not stored locally — they live on the MySigner server, encrypted at rest in the database, and are fetched on demand or brokered through the server during uploads. Android keystore files cached at `~/.mysigner/keystores/*.jks` are plaintext binaries with a 24-hour TTL and `0600` perms; running `mysigner logout` wipes them.

> **CI/CD tip:** in pipelines, set `MYSIGNER_API_TOKEN` (and optionally `MYSIGNER_ORG_ID`, `MYSIGNER_EMAIL`, `MYSIGNER_API_URL`) as encrypted secrets. The CLI uses env vars directly without touching `config.yml`.

> **Tip:** Already have your token? You can skip the wizard and log in directly with `mysigner login`.

---

## Step 4: Connect Your Store Accounts

MySigner needs API access to the stores you want to ship to. Set up one or both depending on your platforms.

### App Store Connect (iOS)

#### Create an API Key in Apple

1. Go to [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
2. Click the **+** button to generate a new key
3. Name it (e.g., "MySigner") and select **Admin** access
4. Click **Generate**
5. **Download the `.p8` file** — you can only download it once
6. Note the **Key ID** and **Issuer ID** shown on the page

#### Add to MySigner

1. In the MySigner dashboard, go to **App Store Connect** in the sidebar
2. Click **Add Credential**
3. Fill in:
   - **Key ID** — the 10-character key ID from Apple
   - **Issuer ID** — the UUID from Apple
   - **Private Key** — open your `.p8` file and paste its contents
4. Click **Save**

MySigner will verify the connection and sync your certificates, provisioning profiles, and registered devices.

### Google Play (Android)

#### Create a Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the **Google Play Android Developer API**
4. Create a **Service Account** and download the JSON key

#### Grant Access in Google Play

1. Open [Google Play Console](https://play.google.com/console/) → **Users and permissions**
2. Invite the service account email with **Release Manager** access (this is the minimum required — Admin works too but grants more than needed)

#### Add to MySigner

1. In the MySigner dashboard, go to **Google Play** in the sidebar and upload the JSON key
2. MySigner will validate the credentials and test the connection

#### Upload Your Keystore

1. Go to **Keystores** in the sidebar
2. Click **Upload Keystore** and upload your `.jks` or `.keystore` file
3. Enter the keystore password, key alias, and key password
4. Click **Activate** to set it as the default signing key

> **Tip:** You can set up either or both platforms later by running `mysigner doctor` — it detects missing credentials and walks you through the setup interactively.

---

## Step 5: Ship Your First Build

Navigate to your project's root directory and run one command. MySigner handles everything else — detecting your framework, building, signing, and uploading.

### iOS to TestFlight

```bash
mysigner ship testflight
```

The CLI will detect your project, run any necessary pre-build steps (e.g., `expo prebuild`, `cap sync`, `flutter pub get`), build an Xcode archive, sign and export to IPA, and upload to TestFlight. Once Apple finishes processing (usually 5-15 minutes), the build appears in TestFlight for your testers.

### iOS to App Store Review

```bash
mysigner ship appstore
```

This does everything `testflight` does, plus it **automatically waits** for Apple to process your build (polling every 3 minutes) and then **submits it for App Store review** — no manual steps needed. One command takes you from source code to "Waiting for Review".

### Android to Google Play

```bash
mysigner ship internal --platform android
```

The CLI detects your framework, builds an AAB (Android App Bundle), fetches your keystore from MySigner, signs the build, and uploads to Google Play. Version codes are **auto-incremented** — if the Play Store already has version code 42, MySigner bumps to 43 automatically, so you never hit "version code already exists" errors.

Ship to any track by changing the target:

| Target | Command |
|--------|---------|
| Internal testing | `mysigner ship internal --platform android` |
| Closed testing (Alpha) | `mysigner ship alpha --platform android` |
| Open testing (Beta) | `mysigner ship beta --platform android` |
| Production | `mysigner ship production --platform android` |

> **Note:** Add `--release-notes "Bug fixes and improvements"` to include release notes with your Android upload.

---

## Step 6: Verify Your Setup

Run the doctor command to make sure everything is configured correctly:

```bash
mysigner doctor
```

Doctor validates your entire environment across both platforms:

| Check | What it verifies |
|-------|-----------------|
| CLI authentication | Token is valid and API is reachable |
| App Store Connect | ASC API key is configured and working |
| Google Play | Service account credentials and permissions |
| Xcode & build tools | Xcode, command line tools, and upload tools |
| Java & Android SDK | JDK, ANDROID_HOME, and Gradle |
| Signing identity | Distribution certificate in your Keychain |
| Keystores | Active Android keystore for signing |
| Project | Detects your project, bundle ID, and required profiles |

If anything is missing or misconfigured, doctor will suggest a fix or offer to resolve it automatically.

---

## Quick Reference

| Command | What it does |
|---------|-------------|
| `mysigner ship testflight` | Build, sign, and upload to TestFlight |
| `mysigner ship appstore` | Build, sign, upload, wait, and submit for App Store review |
| `mysigner ship internal --platform android` | Build, sign, and upload to internal testing |
| `mysigner ship production --platform android` | Build, sign, and upload to production |
| `mysigner doctor` | Check setup and auto-fix issues |
| `mysigner status` | Show connection and credential status |
| `mysigner sync --force` | Refresh data from Apple and Google |
| `mysigner devices` | List registered test devices |
| `mysigner profiles` | List provisioning profiles |
| `mysigner certificates` | List signing certificates |

---

## What's Next

### Learn More Commands

- [Ship Command Reference](/docs/commands/ship) — All shipping options and flags
- [Submit Command](/docs/commands/submit) — Submit existing builds for review
- [Doctor Command](/docs/commands/doctor) — Diagnose and fix issues

### Follow Guides

- [iOS to App Store](/docs/guides/ios-appstore) — Submit for App Store review
- [Android to Play Store](/docs/guides/android-playstore) — Production releases
- [GitHub Actions CI/CD](/docs/guides/ci-cd-github) — Automate with CI/CD

### Explore the Dashboard

**Setup & resources:**
- [Managing Credentials](/docs/dashboard/credentials) — ASC and Google Play setup
- [iOS Resources](/docs/dashboard/ios-resources) — Certificates, profiles, devices
- [Android Resources](/docs/dashboard/android-resources) — Keystores, apps, tracks
- [API Tokens](/docs/dashboard/api-tokens) — Manage scopes (Read / Write / Admin)
- [Notifications](/docs/dashboard/notifications) — Email alerts for expiry, sync failures, revocations, team activity

**Publish & ASO:**
- [Releases](/docs/dashboard/releases) — Store listings, release notes, AI translate / rewrite, release checklists, phased releases
- [Screenshot Studio](/docs/dashboard/screenshot-studio) — Canvas editor for App Store / Play Store screenshots
- [Keywords & ASO](/docs/dashboard/keywords) *(Pro+)* — Edit App Store keywords per locale, track ranks
- [Reviews & Ratings](/docs/dashboard/reviews) — Unified inbox for both stores with response templates *(Pro+)*
- [Analytics](/docs/dashboard/analytics) — Acquisition, retention, stability, monetisation
- [Custom Product Pages](/docs/dashboard/custom-product-pages) *(Pro+)* — iOS CPP variants

**Billing:**
- [14-Day Pro Trial](/docs/dashboard/trial) — How the auto-trial works
- [Pricing & Plans](/docs/dashboard/pricing-plans) — Free vs Pro vs Team

**Team plan features:**
- [Permissions](/docs/dashboard/permissions) — RBAC matrix
- [Audit Log](/docs/dashboard/audit-log) — Immutable record of sensitive actions
- [SSO (SAML 2.0)](/docs/dashboard/sso) — Single sign-on with Okta / Entra / Google Workspace

---

## Troubleshooting

Having issues? Try these in order:

1. **Run doctor** — `mysigner doctor` diagnoses and auto-fixes most problems
2. **Check status** — `mysigner status` verifies your connection and credentials
3. **Force sync** — `mysigner sync --force` refreshes data from Apple and Google
4. **Enable debug** — `DEBUG=1 mysigner ship testflight` for detailed error output

See the [Troubleshooting Guide](/docs/guides/troubleshooting) for solutions to specific error messages.
