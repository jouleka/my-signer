---
title: Release Configuration
description: Configure App Store and Google Play release settings
order: 5
---

# Release Configuration

Configure how your apps are released to the App Store and Google Play, including release notes, phased rollouts, and submission options.

---

## Overview

Release configurations let you predefine settings that are used when shipping builds:

| Platform | Configurable Settings |
|----------|----------------------|
| **iOS** | What's New, release type, phased release, promotional text, URLs |
| **Android** | Track selection, release notes |

For designing the screenshots that go with a release, see [Screenshot Studio](/docs/dashboard/screenshot-studio) — projects, scenes, device frames, and direct uploads to App Store Connect / Google Play.

---

## App Store Releases (iOS)

### Creating a Release Configuration

1. Go to **iOS** → **Apps**
2. Find your app and click on it
3. Click **Configure Release** or go to the Releases section
4. Fill in the release settings
5. Click **Save**

### Release Settings

#### What's New

The release notes shown to users on the App Store update page.

```
• New dark mode support
• Fixed crash when loading images
• Performance improvements
```

**Best practices:**
- Lead with the most important changes
- Use bullet points for readability
- Keep it under 4000 characters
- Localize for each market (if applicable)

#### Promotional Text

Text that appears above the description in the App Store. Can be updated without a new release.

```
🎉 Now with dark mode! Try it today.
```

**Best practices:**
- Use for timely promotions
- Highlight new features
- Update without submitting a new version

#### Support URL

Link to your support page or help center. Required for App Store.

```
https://example.com/support
```

#### Marketing URL

Optional link to your marketing page.

```
https://example.com
```

#### Privacy Policy URL

Link to your privacy policy. Required for apps that collect user data.

```
https://example.com/privacy
```

### Release Types

Choose when your app becomes available after approval:

| Type | Behavior |
|------|----------|
| **Immediately after approval** | App goes live as soon as Apple approves |
| **Manually release** | You control when to release after approval |
| **Scheduled release** | Release on a specific date/time |

#### Immediate Release

Best for:
- Bug fixes that need to go out ASAP
- Features with no marketing coordination needed
- Development/testing apps

#### Manual Release

Best for:
- Coordinating with marketing announcements
- Synchronizing with events or launches
- Staged rollouts to specific markets first

#### Scheduled Release

Best for:
- Timed releases (Monday morning in each timezone)
- Event-based launches
- Coordinated global releases

> **Note:** The scheduled date must be at least 1 hour in the future.

### Phased Release

Gradually roll out your update to users:

| Day | Percentage |
|-----|------------|
| Day 1 | 1% |
| Day 2 | 2% |
| Day 3 | 5% |
| Day 4 | 10% |
| Day 5 | 20% |
| Day 6 | 50% |
| Day 7 | 100% |

**Benefits:**
- Catch issues before affecting all users
- Monitor crash reports gradually
- Pause rollout if problems emerge

**Enabling phased release:**
1. Check **Phased Release** in the configuration
2. Save the configuration
3. Ship with `mysigner ship appstore`

**Pausing phased release:**
- Done through App Store Connect directly (not yet supported in MySigner)

---

## Google Play Releases (Android)

Android releases are configured per track when shipping:

### Track Selection

| Track | Use Case |
|-------|----------|
| `internal` | Quick testing with internal team |
| `alpha` | Closed alpha testing |
| `beta` | Open or closed beta |
| `production` | Public release |

### Staged Rollouts

For production releases, you can manage staged rollouts through the Google Play Console. When shipping with MySigner, your build is uploaded to the specified track:

```bash
# Ship to production track
mysigner ship production --platform android
```

To control rollout percentages (10%, 50%, 100%), manage this directly in Google Play Console after the build is uploaded.

### Release Notes

Provide release notes when shipping:

```bash
mysigner ship production --platform android --release-notes "Bug fixes and improvements"
```

---

## CLI Integration

Release configurations integrate with the CLI `ship` command.

### iOS

```bash
# Ship to TestFlight (uses release config for metadata)
mysigner ship testflight

# Ship to App Store (uses full release config)
mysigner ship appstore
```

When shipping to App Store, MySigner uses your configured:
- What's New
- Promotional Text
- URLs
- Release Type
- Phased Release setting

### Android

```bash
# Ship to internal track
mysigner ship internal --platform android

# Ship to production
mysigner ship production --platform android
```

---

## Store Listings & Localisation

A release in MySigner is a collection of **store listings** — one per locale. Each listing carries the metadata Apple or Google shows on the store page in that language.

### Per-locale fields

Each store listing has its own copy of:

- App name
- Subtitle *(iOS only)*
- Keywords *(iOS only)*
- Short description *(Android only)*
- Description
- Promotional text *(iOS only)*
- What's New / release notes
- Support URL, marketing URL, privacy policy URL

Nothing is shared across locales — each one is an independent set of fields.

### Adding a new locale

1. Open a release and switch to the **Listing** tab
2. Click **Add Locale**
3. Pick from the dropdown of available locales (the list excludes ones you already have)
4. Submit — a new listing is created in `draft` status

### Plan limits on locales

| Tier | Locales per app |
|------|-----------------|
| Free | 1 |
| Pro | 10 |
| Team | unlimited |

If you try to add a locale beyond your plan's limit, you'll see an upgrade prompt instead of the form.

### Sync status

Each listing tracks its sync state with the store:

| Status | Meaning |
|--------|---------|
| `draft` | Created but never pushed |
| `synced` | Matches the version live on the store |
| `modified` | Edited locally since last sync — pending push |
| `partially_synced` | Push succeeded for some fields, failed for others |
| `conflict` | Store changed independently — manual reconciliation needed |

### Pushing listings to the store

Pushing requires Pro or Team (`store_listing_push_enabled`). Click **Push to store** on the release page. MySigner queues a background job per locale that uploads to App Store Connect (iOS) or Google Play (Android). The sync status updates as each job completes.

Pulling from the store (Sync) is available on every plan and works the other direction — fetching the current store metadata into MySigner.

### Primary locale

Each app has a **primary locale** (the source of truth, defaulting to `en-US`). It shows first in the locale picker and serves as the source language when you AI-translate listings to other locales.

---

## Release Notes Review Workflow

When your organisation has more than one member, MySigner unlocks a **review workflow** for release notes — write a draft, submit it for review, and an admin approves or requests changes before it can be applied to a store listing.

### Statuses

A release note moves through these states:

| Status | What it means |
|--------|---------------|
| `draft` | Editable; not yet submitted |
| `pending_review` | Submitted; waiting on an admin |
| `applied` | Approved and applied to a store listing |
| `published` | Live on the store |
| `archived` | Retained for history; no longer in rotation |

### Who can do what

| Action | Required role |
|--------|---------------|
| Create / edit release notes | Developer or higher |
| Submit for review | Developer or higher |
| Approve | Admin or Owner |
| Request changes (reject) | Admin or Owner |
| Delete a release note | Admin or Owner |

> **Single-seat orgs:** the review workflow only activates when your organisation has 2+ members. If you're solo, you can write and apply release notes directly without the review step.

### Workflow

1. Developer writes a release note in **draft** status
2. Developer clicks **Submit for Review** → status flips to `pending_review`
3. A **pending review** badge appears on the release page and in the sidebar count badge
4. Admin opens the release, reviews the note, and either:
   - Clicks **Approve** → status returns to `draft` (now ready to apply); approver and timestamp recorded
   - Clicks **Request Changes** → status returns to `draft` with the rejection comment shown to the developer
5. Developer addresses comments (if any) and re-submits, or applies the now-approved note to a store listing

---

## AI Translate / Rewrite

MySigner uses AI to translate store-listing fields into your other locales and to rewrite release notes from raw input (commit messages, bullet lists, etc.).

### Translatable fields

| Field | Where |
|-------|-------|
| App name | Listing |
| Subtitle | Listing (iOS) |
| Keywords | Listing (iOS) |
| Description | Listing |
| Promotional text | Listing (iOS) |
| Short description | Listing (Android) |
| What's New / release notes | Release note |

### Monthly quotas

Quotas reset on the **1st of each calendar month**.

| Tier | Translations / month | Rewrites / month |
|------|---------------------:|-----------------:|
| Free | 5 | 3 |
| Pro | 100 | 50 |
| Team | 500 | 200 |

The **Translate** and **AI Rewrite** buttons each show a remaining-count badge, and disable when you hit zero. Quotas are debited optimistically and refunded automatically if the translation/rewrite job fails.

### Translating a release note

1. Open the release and switch to the **What's New** tab
2. Click **Translate to all locales**
3. MySigner finds every locale your app supports and translates the source release note to each one
4. Translations are stored on the release note and can be reviewed/edited per locale before the listing is pushed

### Translating store listing fields

1. Open the release and switch to the **Listing** tab
2. Pick a target locale tab (must already exist — add it first if not)
3. Click **AI Translate** — the source is the primary locale's listing
4. Edit the translated fields if needed, then save

### AI Rewrite

The **AI Rewrite** modal lets you turn raw input into a polished release note:

1. Open the **What's New** tab and click **AI Rewrite**
2. Paste your raw text — commit messages, bullet points, or change-log lines
3. Or click **Fetch from GitHub** to pull recent commits from your linked repo
4. Submit and the rewritten release note appears as a new draft you can edit

---

## Release Checklists

Every release page has a **Release Checklist** tab — a pre-flight check covering the items you should review before submission. Standard items are managed by MySigner; custom items let you add team-specific verifications.

### Standard items

Six items are tracked by default:

- Release notes written
- All locales translated
- Screenshots updated
- Description reviewed
- Build tested
- Privacy policy current

Each item has a checkbox, a label, and a category. The header shows a progress bar and a "Ready for submission" badge when every required item is checked.

### Auto-detected items

Above the manual checklist, MySigner adds **auto-detected** items computed from your app's current state — e.g. flagging a release note that hasn't been approved yet, or screenshots that don't match the device frames Apple expects. These don't count toward the "ready for submission" gate, but they're useful warnings.

### Custom items *(Pro+)*

Pro and Team plans can add their own checklist items. Each custom item has:

- A label (e.g. "QA tested on iPhone 11")
- A required / optional flag

Optional items show in the list but don't block the "ready for submission" badge.

### Plan limits

| | Free | Pro | Team |
|---|------|-----|------|
| Release checklist | Read-only | Editable + custom items | Editable + custom items |

On Free, the standard items show but the checkboxes are inert. Upgrading unlocks them and the custom-item form.

### When the checklist appears

- As a tab on every release page
- Inline as a guard before push/submit operations, so you see what's outstanding without leaving the flow

---

## API Integration

For CI/CD pipelines, you can update release configurations via the API:

```bash
# Update What's New
curl -X PATCH https://mysigner.dev/api/v1/organizations/{org_id}/app_store_releases/{id} \
  -H "Authorization: Bearer $MYSIGNER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"whats_new": "New features..."}'
```


---

## Best Practices

### Prepare in Advance

1. Update release configuration before building
2. Write What's New while changes are fresh
3. Review configuration before shipping

### Version Control Release Notes

Store release notes in your repository:

```
/releases
  /1.2.0.md
  /1.2.1.md
  /1.3.0.md
```

Update the MySigner configuration as part of your release process.

### Phased Rollouts

1. **Start small** - Begin with 1-10% for major updates
2. **Monitor metrics** - Watch crash reports and reviews
3. **Pause if needed** - Stop rollout if issues arise
4. **Communicate** - Let users know a new version is rolling out

### Coordinated Releases

For simultaneous iOS/Android releases:

1. Ship Android to internal track
2. Ship iOS to TestFlight
3. Test on both platforms
4. Submit iOS to App Store
5. Prepare Android for production
6. Release both when iOS is approved

---

## Troubleshooting

### "Release configuration not found"

The bundle ID doesn't have a release configuration.

**Fix:** Create one from the app's page in the dashboard.

### "What's New is too long"

App Store limits release notes to 4000 characters.

**Fix:** Shorten your release notes or link to a changelog.

### "Invalid release date"

Scheduled release date must be in the future.

**Fix:** Set a date at least 1 hour from now.

### "Phased release already in progress"

You can only have one phased release at a time.

**Fix:** Wait for current phased release to complete or release immediately.

---

## Related

- [iOS to App Store](/docs/guides/ios-appstore) - Complete App Store submission guide
- [Android to Play Store](/docs/guides/android-playstore) - Complete Play Store guide
- [Ship Command](/docs/commands/ship) - CLI shipping reference
- [Submit Command](/docs/commands/submit) - Manual submission
