---
title: GitLab CI
description: Automate your app deployment with GitLab CI/CD
order: 6
---

# GitLab CI

This guide shows you how to set up automated iOS and Android deployment using GitLab CI/CD with MySigner.

---

## Prerequisites

- MySigner account with API token
- App Store Connect credential configured (for iOS)
- Google Play credential configured (for Android)
- GitLab repository with your mobile app

---

## GitLab CI/CD Variables

Add these variables to your GitLab project:

1. Go to **Settings** → **CI/CD** → **Variables**
2. Add the following variables:

| Variable | Required | Type | Description | Protected | Masked |
|----------|----------|------|-------------|-----------|--------|
| `MYSIGNER_API_TOKEN` | Yes | Variable | Your MySigner API token | ✓ | ✓ |
| `MYSIGNER_ORG_ID` | Yes | Variable | Your organization ID (find in dashboard URL or `mysigner status`) | ✓ | |
| `MYSIGNER_API_URL` | No | Variable | Your MySigner dashboard URL (defaults to `https://mysigner.dev`) | ✓ | |
| `MYSIGNER_EMAIL` | No | Variable | The email associated with your MySigner account | ✓ | |

> **Tip:** Enable "Protected" for production variables so they're only available on protected branches.

### Authentication in CI

The CLI automatically detects environment variables — no config file needed. GitLab CI/CD variables are automatically available as environment variables in every job, so just set them once and every `mysigner` command will work.

---

## iOS Configuration

Create `.gitlab-ci.yml` for iOS TestFlight deployment:

```yaml
stages:
  - build
  - deploy

.macos_runner:
  tags:
    - macos
    - xcode
  before_script:
    - gem install mysigner

# TestFlight Deployment
deploy_testflight:
  extends: .macos_runner
  stage: deploy
  script:
    - mysigner doctor
    - mysigner ship testflight --verbose
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_COMMIT_BRANCH == "develop"
  artifacts:
    paths:
      - "*.ipa"
    expire_in: 1 week

# App Store Deployment
deploy_appstore:
  extends: .macos_runner
  stage: deploy
  script:
    - mysigner ship appstore --verbose
  rules:
    - if: $CI_COMMIT_TAG
      when: manual
```

---

## Android Configuration

For Android deployments:

```yaml
stages:
  - build
  - deploy

.android_runner:
  image: eclipse-temurin:17-jdk
  tags:
    - docker
  before_script:
    - apt-get update -qq && apt-get install -y -qq ruby ruby-dev build-essential
    - gem install mysigner

# Internal Testing
deploy_internal:
  extends: .android_runner
  stage: deploy
  script:
    - mysigner ship internal --platform android --verbose
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  artifacts:
    paths:
      - "app/build/outputs/bundle/release/*.aab"
    expire_in: 1 week

# Production Deployment
deploy_production:
  extends: .android_runner
  stage: deploy
  script:
    - mysigner ship production --platform android --verbose
  rules:
    - if: $CI_COMMIT_TAG
      when: manual
```

---

## Combined iOS & Android Pipeline

Full configuration for both platforms:

```yaml
stages:
  - test
  - build
  - deploy

# ==========================================
# iOS Jobs (macOS Runner)
# ==========================================

.ios_base:
  tags:
    - macos
    - xcode
  before_script:
    - gem install mysigner

ios:testflight:
  extends: .ios_base
  stage: deploy
  script:
    - mysigner doctor
    - mysigner ship testflight --verbose
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_COMMIT_BRANCH == "develop"
  artifacts:
    paths:
      - "*.ipa"
    expire_in: 1 week

ios:appstore:
  extends: .ios_base
  stage: deploy
  script:
    - mysigner ship appstore --verbose
  rules:
    - if: $CI_COMMIT_TAG
      when: manual
  allow_failure: false

# ==========================================
# Android Jobs (Docker Runner)
# ==========================================

.android_base:
  image: eclipse-temurin:17-jdk
  tags:
    - docker
  before_script:
    - apt-get update -qq && apt-get install -y -qq ruby ruby-dev build-essential
    - gem install mysigner
  cache:
    key: gradle-cache
    paths:
      - .gradle/
      - android/.gradle/

android:internal:
  extends: .android_base
  stage: deploy
  script:
    - mysigner ship internal --platform android --verbose
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
    - if: $CI_COMMIT_BRANCH == "develop"
  artifacts:
    paths:
      - "app/build/outputs/bundle/release/*.aab"
    expire_in: 1 week

android:production:
  extends: .android_base
  stage: deploy
  script:
    - mysigner ship production --platform android --verbose
  rules:
    - if: $CI_COMMIT_TAG
      when: manual
  allow_failure: false
```

---

## Self-Hosted macOS Runner

For iOS builds, you need a macOS runner. Set up a GitLab Runner on your Mac:

### Install GitLab Runner

```bash
brew install gitlab-runner
```

### Register the Runner

```bash
gitlab-runner register
```

Follow the prompts:
1. Enter your GitLab URL
2. Enter the registration token (from Settings → CI/CD → Runners)
3. Enter a description (e.g., "macOS Build Machine")
4. Enter tags: `macos,xcode`
5. Choose executor: `shell`

### Start the Runner

```bash
gitlab-runner install
gitlab-runner start
```

---

## Caching

Speed up builds with caching:

### iOS (CocoaPods)

```yaml
ios:testflight:
  cache:
    key: cocoapods-$CI_COMMIT_REF_SLUG
    paths:
      - Pods/
      - .cocoapods/
  script:
    - pod install --deployment
    - mysigner ship testflight
```

### Android (Gradle)

```yaml
android:internal:
  cache:
    key: gradle-$CI_COMMIT_REF_SLUG
    paths:
      - .gradle/
      - ~/.gradle/caches/
      - ~/.gradle/wrapper/
```

---

## Environment-Specific Deployments

### Using GitLab Environments

```yaml
deploy_testflight:
  stage: deploy
  environment:
    name: testflight
    url: https://appstoreconnect.apple.com/
  script:
    - mysigner ship testflight

deploy_production:
  stage: deploy
  environment:
    name: production
    url: https://apps.apple.com/app/your-app-id
  script:
    - mysigner ship appstore
  when: manual
```

---

## Scheduled Pipelines

Set up nightly builds:

1. Go to **Build** → **Pipeline schedules**
2. Create a new schedule
3. Set the cron expression (e.g., `0 2 * * *` for 2 AM daily)
4. Set variables if needed

```yaml
nightly_build:
  stage: build
  script:
    - mysigner ship testflight
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
```

---

## Merge Request Pipelines

Run validation on merge requests:

```yaml
validate:
  stage: test
  script:
    - mysigner doctor
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

---

## Notifications

### Slack Notifications

```yaml
.notify_slack:
  after_script:
    - |
      if [ "$CI_JOB_STATUS" == "success" ]; then
        curl -X POST -H 'Content-type: application/json' \
          --data "{\"text\":\"✅ $CI_PROJECT_NAME deployed to $CI_ENVIRONMENT_NAME\"}" \
          $SLACK_WEBHOOK_URL
      fi

deploy_testflight:
  extends: .notify_slack
  # ... rest of config
```

### Email Notifications

Configure in GitLab project settings under **Settings** → **Integrations** → **Emails on push**.

---

## Troubleshooting

### "Runner not available"

No runner with matching tags.

**Fix:**
1. Check runner is online in **Settings** → **CI/CD** → **Runners**
2. Verify tags match between job and runner
3. For shared runners, ensure they support your platform

### "Permission denied" on macOS

Ruby gem installation issues.

**Fix:**
```yaml
before_script:
  - export GEM_HOME="$HOME/.gem"
  - export PATH="$GEM_HOME/bin:$PATH"
  - gem install mysigner
```

### Job timeout

Build takes too long.

**Fix:**
```yaml
deploy_appstore:
  timeout: 2 hours  # Increase timeout
  script:
    - mysigner ship appstore
```

### Variable not available

Protected variable on unprotected branch.

**Fix:**
1. Make the branch protected, or
2. Uncheck "Protected" on the variable

---

## Best Practices

### Branch Strategy

| Branch | Deployment | Track |
|--------|------------|-------|
| `develop` | Automatic | TestFlight / Internal |
| `main` | Automatic | TestFlight / Beta |
| Tags | Manual | App Store / Production |

### Artifact Management

```yaml
artifacts:
  paths:
    - "*.ipa"
    - "*.aab"
  expire_in: 2 weeks
  when: on_success
```

### Security

1. Use protected variables for sensitive data
2. Limit protected branches
3. Use masked variables for tokens
4. Rotate API tokens regularly

---

## Related

- [GitHub Actions Integration](/docs/guides/ci-cd-github)
- [Bitrise Integration](/docs/guides/ci-cd-bitrise)
- [Ship Command Reference](/docs/commands/ship)
- [API Tokens](/docs/dashboard/api-tokens) — Token scopes and rotation best practices for CI/CD
- [Notifications](/docs/dashboard/notifications) — Sync Failures + Revocations alerts to catch CI breakage early

> **Pricing note:** the MySigner CLI is free on every plan tier — there's no per-pipeline / per-build CLI cost.
