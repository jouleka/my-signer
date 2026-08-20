---
title: GitHub Actions
description: Automate iOS and Android deployment with GitHub Actions
order: 1
---

# GitHub Actions

Automate your iOS and Android deployments with GitHub Actions. One push to `main` can build, sign, and ship your app to TestFlight, the App Store, or Google Play — hands-free.

---

## Prerequisites

Before setting up your workflows, make sure you have:

- A MySigner account with an API token ([generate one here](/docs/quickstart/getting-started#generate-an-api-token))
- **For iOS:** App Store Connect credentials configured in your MySigner dashboard
- **For Android:** Google Play credentials and keystore uploaded to your MySigner dashboard
- A GitHub repository with your mobile app

---

## Repository Setup

### Add Secrets

Your MySigner credentials need to be stored as encrypted GitHub secrets. Go to your repository's **Settings** → **Secrets and variables** → **Actions** and add:

| Secret | Required | Description |
|--------|----------|-------------|
| `MYSIGNER_API_TOKEN` | Yes | Your MySigner API token |
| `MYSIGNER_ORG_ID` | Yes | Your organization ID (find it in the dashboard URL or `mysigner status`) |
| `MYSIGNER_API_URL` | No | Your MySigner dashboard URL (defaults to `https://mysigner.dev`) |
| `MYSIGNER_EMAIL` | No | The email associated with your MySigner account |
| `MYSIGNER_KEYSTORE_PASSWORD` | Android only | Keystore password, used when the CLI needs to re-sign a downloaded keystore non-interactively |
| `MYSIGNER_KEY_PASSWORD` | Android only | Key password (falls back to `MYSIGNER_KEYSTORE_PASSWORD` if unset) |
| `MYSIGNER_KEYSTORE_CACHE_HOURS` | No | TTL for the local keystore cache, in hours (default: `24`) |
| `MYSIGNER_VERBOSE` | No | Set to `1` for extra diagnostic logging (in addition to `--verbose`) |

### Authentication in CI

The CLI automatically detects environment variables — no config file needed. Just pass the secrets as `env` in your workflow steps:

```yaml
- name: Ship to TestFlight
  run: mysigner ship testflight --verbose
  env:
    MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
    MYSIGNER_ORG_ID: ${{ secrets.MYSIGNER_ORG_ID }}
```

That's it. When `MYSIGNER_API_TOKEN` and `MYSIGNER_ORG_ID` are set, the CLI uses them directly — no config file, no setup step.

> **Tip:** You can also set `MYSIGNER_API_URL` and `MYSIGNER_EMAIL` as environment variables if needed, but they're optional (the URL defaults to `https://mysigner.dev`).

---

## iOS Workflows

iOS builds require macOS runners (`runs-on: macos-latest`) since Xcode is needed.

### TestFlight

Deploy beta builds to TestFlight on every push to `main`. Create `.github/workflows/ios-testflight.yml`:

```yaml
name: iOS TestFlight

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: macos-latest
    timeout-minutes: 30
    env:
      MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
      MYSIGNER_ORG_ID: ${{ secrets.MYSIGNER_ORG_ID }}

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'

      - name: Install MySigner
        run: gem install mysigner

      - name: Ship to TestFlight
        run: mysigner ship testflight --verbose
```

This builds your project, signs it, and uploads to TestFlight. The build will appear for your testers after Apple finishes processing (usually 5-15 minutes).

### App Store Review

Submit directly to App Store review — MySigner automatically waits for Apple to process the build, then submits it for review. Create `.github/workflows/ios-appstore.yml`:

```yaml
name: iOS App Store

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: macos-latest
    timeout-minutes: 60
    env:
      MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
      MYSIGNER_ORG_ID: ${{ secrets.MYSIGNER_ORG_ID }}

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'

      - name: Install MySigner
        run: gem install mysigner

      - name: Ship to App Store
        run: mysigner ship appstore --verbose
```

The `appstore` target does the heavy lifting: build, sign, upload, poll every 3 minutes until Apple processes the build, and then auto-submit for App Store review. One command, zero manual steps.

> **Tip:** Use the `release` trigger to deploy to the App Store only when you create a GitHub release — keeping production deploys intentional.

---

## Android Workflows

Android builds can run on `ubuntu-latest` (no macOS needed), which is faster and cheaper.

### Internal Testing

Deploy to the internal testing track on every push to `main`. Create `.github/workflows/android-internal.yml`:

```yaml
name: Android Internal

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    env:
      MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
      MYSIGNER_ORG_ID: ${{ secrets.MYSIGNER_ORG_ID }}

    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'

      - name: Install MySigner
        run: gem install mysigner

      - name: Ship to Internal Testing
        run: mysigner ship internal --platform android --verbose
```

MySigner auto-increments your version code if it conflicts with an existing build on Google Play, so you'll never hit "version code already exists" errors in CI.

### Production

Deploy to production when you create a GitHub release. Create `.github/workflows/android-production.yml`:

```yaml
name: Android Production

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    env:
      MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
      MYSIGNER_ORG_ID: ${{ secrets.MYSIGNER_ORG_ID }}

    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'

      - name: Install MySigner
        run: gem install mysigner

      - name: Ship to Production
        run: |
          mysigner ship production --platform android \
            --release-notes "Release ${{ github.event.release.tag_name }}" \
            --verbose
```

This pulls release notes from your GitHub release tag automatically.

---

## Both Platforms in One Workflow

If your project targets both iOS and Android, run them in parallel. Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  ios:
    runs-on: macos-latest
    timeout-minutes: 30
    env:
      MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
      MYSIGNER_ORG_ID: ${{ secrets.MYSIGNER_ORG_ID }}
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
      - run: gem install mysigner
      - run: mysigner ship testflight --verbose

  android:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    env:
      MYSIGNER_API_TOKEN: ${{ secrets.MYSIGNER_API_TOKEN }}
      MYSIGNER_ORG_ID: ${{ secrets.MYSIGNER_ORG_ID }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
      - run: gem install mysigner
      - run: mysigner ship internal --platform android --verbose
```

Both jobs run in parallel — iOS on macOS, Android on Ubuntu — so your total deploy time is only as long as the slower build.

---

## Best Practices

### Add Caching

Speed up your builds by caching dependencies:

```yaml
# iOS — cache CocoaPods
- name: Cache CocoaPods
  uses: actions/cache@v4
  with:
    path: Pods
    key: pods-${{ hashFiles('Podfile.lock') }}

# Android — cache Gradle
- name: Cache Gradle
  uses: actions/cache@v4
  with:
    path: |
      ~/.gradle/caches
      ~/.gradle/wrapper
    key: gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
```

### iOS Version Bumping

MySigner auto-increments Android version codes, but iOS build numbers need to be managed separately. Use `agvtool` with the GitHub Actions run number for automatic incrementing:

```yaml
- name: Set build number
  run: agvtool new-version -all ${{ github.run_number }}
```

Place this step before the `mysigner ship` step.

### Notifications

Add a Slack notification on deploy success:

```yaml
- name: Notify on Success
  if: success()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Deployed ${{ github.repository }} (${{ github.ref_name }})"
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

### Manual Triggers

All the workflows above include `workflow_dispatch`, which adds a **Run workflow** button in the GitHub Actions UI. This lets you trigger a deploy manually without pushing code — useful for hotfixes or re-deploys.

---

## Troubleshooting

### Build fails with signing error

- Verify your App Store Connect credentials are active in the MySigner dashboard
- Check that the signing certificate is valid: `mysigner certificates`
- Run `mysigner doctor` locally to diagnose the issue

### Upload times out

- Large apps or slow connections can cause timeouts
- Make sure your job has enough time: `timeout-minutes: 60` (or higher for App Store submissions)
- The `appstore` target needs extra time for Apple's build processing (up to 30 minutes)

### Ruby version mismatch

> `Error: mysigner requires Ruby version >= 3.2`

Ensure your workflow uses `ruby-version: '3.2'` or newer in the `ruby/setup-ruby` step.

### Authentication issues

If the CLI can't find credentials, double-check that:
- Both required secrets (`MYSIGNER_API_TOKEN` and `MYSIGNER_ORG_ID`) are set in your repository
- The `env:` block is applied to the correct job or step in your workflow
- Run `mysigner status --verbose` as a debug step to verify the configuration loaded correctly

---

## Related

- [GitLab CI Integration](/docs/guides/ci-cd-gitlab) — GitLab CI/CD setup
- [Bitrise Integration](/docs/guides/ci-cd-bitrise) — Bitrise workflow setup
- [Ship Command Reference](/docs/commands/ship) — All shipping options and flags
- [API Tokens](/docs/dashboard/api-tokens) — Token scopes (Read/Write/Admin), rotation, and per-pipeline best practices
- [Notifications](/docs/dashboard/notifications) — Enable Sync Failures + Revocations alerts so a broken pipeline reaches you outside of GitHub
- [Troubleshooting](/docs/guides/troubleshooting) — Solutions for common errors

> **Pricing note:** the MySigner CLI is free on every plan tier — there's no per-pipeline / per-build CLI cost. Plan limits apply only to web-app features.
