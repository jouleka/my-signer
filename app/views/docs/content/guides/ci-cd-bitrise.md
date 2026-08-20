---
title: Bitrise
description: Automate your app deployment with Bitrise CI/CD
order: 7
---

# Bitrise

This guide shows you how to set up automated iOS and Android deployment using Bitrise with MySigner.

---

## Prerequisites

- MySigner account with API token
- App Store Connect credential configured (for iOS)
- Google Play credential configured (for Android)
- Bitrise account with your app connected

---

## Bitrise Secrets

Add these secrets to your Bitrise app:

1. Go to **Workflow Editor** → **Secrets**
2. Add the following secrets:

| Key | Required | Description |
|-----|----------|-------------|
| `MYSIGNER_API_TOKEN` | Yes | Your MySigner API token |
| `MYSIGNER_ORG_ID` | Yes | Your organization ID (find in dashboard URL or `mysigner status`) |
| `MYSIGNER_API_URL` | No | Your MySigner dashboard URL (defaults to `https://mysigner.dev`) |
| `MYSIGNER_EMAIL` | No | The email associated with your MySigner account |

> **Tip:** Secrets are encrypted and hidden in build logs.

### Authentication in CI

The CLI automatically detects environment variables — no config file needed. Bitrise secrets are automatically available as environment variables in every step, so just install the gem and run your command:

```yaml
- script@1:
    title: Install MySigner
    inputs:
      - content: |
          #!/bin/bash
          set -ex
          gem install mysigner
```

---

## iOS Workflow

### TestFlight Deployment

Create or modify your `bitrise.yml`:

```yaml
format_version: "11"
default_step_lib_source: https://github.com/bitrise-io/bitrise-steplib.git

app:
  envs:
    - BITRISE_PROJECT_PATH: MyApp.xcworkspace
    - BITRISE_SCHEME: MyApp

workflows:
  deploy-testflight:
    steps:
      - activate-ssh-key@4:
          run_if: '{{getenv "SSH_RSA_PRIVATE_KEY" | ne ""}}'

      - git-clone@8: {}

      - cache-pull@2: {}

      - cocoapods-install@2: {}

      - script@1:
          title: Install MySigner
          inputs:
            - content: |
                #!/bin/bash
                set -ex
                gem install mysigner

      - script@1:
          title: Ship to TestFlight
          inputs:
            - content: |
                #!/bin/bash
                set -ex
                mysigner ship testflight --verbose

      - cache-push@2: {}

      - deploy-to-bitrise-io@2: {}
```

### App Store Deployment

```yaml
workflows:
  deploy-appstore:
    steps:
      - activate-ssh-key@4:
          run_if: '{{getenv "SSH_RSA_PRIVATE_KEY" | ne ""}}'

      - git-clone@8: {}

      - cache-pull@2: {}

      - cocoapods-install@2: {}

      - script@1:
          title: Install MySigner
          inputs:
            - content: |
                #!/bin/bash
                set -ex
                gem install mysigner

      - script@1:
          title: Ship to App Store
          inputs:
            - content: |
                #!/bin/bash
                set -ex
                mysigner ship appstore --verbose

      - cache-push@2: {}
```

---

## Android Workflow

### Internal Testing Deployment

```yaml
workflows:
  deploy-android-internal:
    steps:
      - activate-ssh-key@4:
          run_if: '{{getenv "SSH_RSA_PRIVATE_KEY" | ne ""}}'

      - git-clone@8: {}

      - cache-pull@2: {}

      - install-missing-android-tools@3:
          inputs:
            - gradlew_path: "$PROJECT_LOCATION/gradlew"

      - script@1:
          title: Install MySigner
          inputs:
            - content: |
                #!/bin/bash
                set -ex
                gem install mysigner

      - script@1:
          title: Ship to Internal Testing
          inputs:
            - content: |
                #!/bin/bash
                set -ex
                mysigner ship internal --platform android --verbose

      - cache-push@2: {}

      - deploy-to-bitrise-io@2: {}
```

### Production Deployment

```yaml
workflows:
  deploy-android-production:
    steps:
      - activate-ssh-key@4: {}
      - git-clone@8: {}
      - cache-pull@2: {}

      - install-missing-android-tools@3:
          inputs:
            - gradlew_path: "$PROJECT_LOCATION/gradlew"

      - script@1:
          title: Install MySigner
          inputs:
            - content: |
                #!/bin/bash
                set -ex
                gem install mysigner

      - script@1:
          title: Ship to Production
          inputs:
            - content: |
                #!/bin/bash
                set -ex
                mysigner ship production --platform android --verbose

      - cache-push@2: {}
```

---

## Combined iOS & Android Workflow

Full workflow for both platforms:

```yaml
format_version: "11"
default_step_lib_source: https://github.com/bitrise-io/bitrise-steplib.git

app:
  envs:
    - BITRISE_PROJECT_PATH: MyApp.xcworkspace
    - BITRISE_SCHEME: MyApp

trigger_map:
  - push_branch: main
    workflow: deploy-all
  - push_branch: develop
    workflow: deploy-testflight
  - tag: "v*"
    workflow: deploy-production

workflows:
  # Shared setup
  _setup:
    steps:
      - activate-ssh-key@4:
          run_if: '{{getenv "SSH_RSA_PRIVATE_KEY" | ne ""}}'
      - git-clone@8: {}
      - cache-pull@2: {}
      - script@1:
          title: Install MySigner
          inputs:
            - content: gem install mysigner

  # iOS TestFlight
  deploy-testflight:
    before_run:
      - _setup
    steps:
      - cocoapods-install@2: {}
      - script@1:
          title: Ship to TestFlight
          inputs:
            - content: |
                mysigner ship testflight --verbose
      - cache-push@2: {}

  # Android Internal
  deploy-android-internal:
    before_run:
      - _setup
    steps:
      - install-missing-android-tools@3: {}
      - script@1:
          title: Ship to Internal
          inputs:
            - content: |
                mysigner ship internal --platform android --verbose
      - cache-push@2: {}

  # Deploy Both (runs sequentially)
  deploy-all:
    before_run:
      - deploy-testflight
      - deploy-android-internal
    steps: []

  # Production Releases
  deploy-production:
    before_run:
      - _setup
    steps:
      - cocoapods-install@2: {}
      - script@1:
          title: Ship iOS to App Store
          inputs:
            - content: |
                mysigner ship appstore --verbose
      - install-missing-android-tools@3: {}
      - script@1:
          title: Ship Android to Production
          inputs:
            - content: |
                mysigner ship production --platform android --verbose
      - cache-push@2: {}
```

---

## Trigger Configuration

### Push-Based Triggers

```yaml
trigger_map:
  - push_branch: main
    workflow: deploy-testflight
  - push_branch: develop
    workflow: deploy-testflight
  - push_branch: release/*
    workflow: deploy-appstore
```

### Tag-Based Triggers

```yaml
trigger_map:
  - tag: "v*"
    workflow: deploy-production
  - tag: "beta-*"
    workflow: deploy-testflight
```

### Pull Request Triggers

```yaml
trigger_map:
  - pull_request_source_branch: "*"
    workflow: validate
```

---

## Caching

### iOS (CocoaPods)

```yaml
- cache-pull@2:
    inputs:
      - is_debug_mode: "false"

# After pod install
- cache-push@2:
    inputs:
      - cache_paths: |
          ./Pods
          ~/.cocoapods
      - ignore_check_on_paths: |
          .git
```

### Android (Gradle)

```yaml
- cache-pull@2:
    inputs:
      - is_debug_mode: "false"

# After build
- cache-push@2:
    inputs:
      - cache_paths: |
          ~/.gradle/caches
          ~/.gradle/wrapper
          .gradle
      - ignore_check_on_paths: |
          .git
```

---

## Notifications

### Slack Integration

```yaml
- slack@3:
    inputs:
      - webhook_url: $SLACK_WEBHOOK_URL
      - channel: "#deployments"
      - message: |
          Build $BITRISE_BUILD_NUMBER deployed to TestFlight
          App: $BITRISE_APP_TITLE
          Branch: $BITRISE_GIT_BRANCH
      - message_on_error: |
          ⚠️ Build failed!
          App: $BITRISE_APP_TITLE
          Branch: $BITRISE_GIT_BRANCH
```

### Email Notifications

Configure in **App Settings** → **Notifications** → **Email notifications**.

---

## Stack Selection

### For iOS Builds

Select a macOS stack with Xcode:

1. Go to **Workflow Editor** → **Stacks & Machines**
2. Select: `osx-xcode-15.0.x` (or your required Xcode version)

### For Android Builds

Use the default Linux stack or select:

1. Go to **Workflow Editor** → **Stacks & Machines**  
2. Select: `linux-docker-android-20.0.x`

---

## Environment Variables

### App-Level Variables

Set in **App Settings** → **Env Vars**:

```
BITRISE_PROJECT_PATH=MyApp.xcworkspace
BITRISE_SCHEME=MyApp
PROJECT_LOCATION=./android
```

### Workflow-Level Variables

```yaml
workflows:
  deploy-testflight:
    envs:
      - DEPLOY_TARGET: testflight
    steps:
      # ...
```

---

## Troubleshooting

### "Bundle install failed"

Ruby gems not installing correctly.

**Fix:**
```yaml
- script@1:
    inputs:
      - content: |
          #!/bin/bash
          set -ex
          # Use system Ruby
          gem install --user-install mysigner
          export PATH="$PATH:$(ruby -e 'puts Gem.user_dir')/bin"
          mysigner version
```

### Build timeout

Default timeout is 30 minutes.

**Fix:**
1. Go to **Workflow Editor** → **Stacks & Machines**
2. Increase "Max time" (up to 90 minutes on free tier)

### "Codesigning failed"

Signing configuration issues.

**Fix:**
```yaml
- script@1:
    title: Diagnose Signing
    inputs:
      - content: |
          mysigner doctor
```

### Cache not working

Verify cache paths are correct.

**Fix:**
```yaml
- cache-push@2:
    inputs:
      - cache_paths: |
          $HOME/.gradle/caches
          $HOME/.gradle/wrapper
      - is_debug_mode: "true"  # Enable debug to see what's cached
```

---

## Best Practices

### Workflow Organization

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `validate` | PR | Run doctor, tests |
| `deploy-testflight` | Push to `develop` | Internal testing |
| `deploy-beta` | Push to `main` | External beta |
| `deploy-production` | Tag `v*` | Store release |

### Build Numbers

Bitrise provides `$BITRISE_BUILD_NUMBER`. Use it for versioning:

```yaml
- script@1:
    inputs:
      - content: |
          # iOS: Set build number
          agvtool new-version -all $BITRISE_BUILD_NUMBER
```

### Parallel Builds

Run iOS and Android in parallel using Bitrise Pipelines:

```yaml
pipelines:
  deploy-all:
    stages:
      - deploy-both:
          workflows:
            - deploy-testflight: {}
            - deploy-android-internal: {}
```

> **Note:** Pipelines require Bitrise's pipeline-enabled plans. With `before_run`, workflows run sequentially instead.

---

## Related

- [GitHub Actions Integration](/docs/guides/ci-cd-github)
- [GitLab CI Integration](/docs/guides/ci-cd-gitlab)
- [Ship Command Reference](/docs/commands/ship)
- [API Tokens](/docs/dashboard/api-tokens) — Token scopes and rotation best practices for CI/CD
- [Notifications](/docs/dashboard/notifications) — Sync Failures + Revocations alerts to catch CI breakage early

> **Pricing note:** the MySigner CLI is free on every plan tier — there's no per-pipeline / per-build CLI cost.
