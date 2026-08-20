---
title: Reviews & Ratings
description: Monitor reviews from both stores and reply with reusable templates
order: 10
---

# Reviews & Ratings

A unified inbox for App Store and Google Play reviews. Filter by app / platform / rating / sentiment, reply directly from MySigner, and save common responses as templates so the next reply is one click.

---

## Overview

The page pulls reviews from:

- **App Store Connect Customer Reviews API** for iOS apps
- **Google Play Developer Reviews API** for Android apps

It also surfaces Apple's own AI **Review Summarisations** when available (cached for one hour), so you can scan the high-level themes without reading every individual review.

A stats bar at the top shows:

- **Average Rating**
- **Total Reviews**
- **Negative** (1- and 2-star count)
- **Unanswered** count

A 30-day **Rating Trend** card sits below to make movement obvious.

---

## Plan limits

| Capability | Free | Pro | Team |
|------------|------|-----|------|
| Review monitoring | ✓ (up to 1 app) | ✓ (up to 5 apps) | ✓ (up to 999 apps) |
| Reply to reviews | ✓ | ✓ | ✓ |
| Response templates | ✗ | ✓ | ✓ |

If your organisation has more apps than the plan allows, MySigner picks the first matching apps within the limit (Apple apps prioritised) and shows the rest in a locked state until you upgrade.

---

## Filtering

Use the dropdowns at the top of the feed to scope what you see:

- **App** — pick a specific Apple or Android app, or all
- **Platform** — App Store / Google Play
- **Rating** — 1 to 5 stars
- **Sentiment** — positive / neutral / negative (computed automatically based on rating)

---

## Replying to a review

Each review row shows the platform, star rating, sentiment badge, and reply status (`none`, `pending`, `posted`, or `failed`).

1. Click **Reply** on a review
2. Optionally pick a saved template — its content drops into the textarea
3. Edit the reply
4. Submit

Replies are sent in the background. The status badge updates from `pending` → `posted` (or `failed` with an error you can retry).

### Character limits

| Store | Limit |
|-------|-------|
| App Store | 5,970 characters |
| Google Play | 350 characters |

The textarea shows a live counter and refuses to submit if you go over.

### Deleting an Apple reply

You can withdraw a reply you've posted to the App Store. Removing it calls Apple's API and clears the record from MySigner.

> Google Play does not support deleting a posted reply through the API. To withdraw a Play Store reply, edit it through Google Play Console.

---

## Response templates *(Pro+)*

Templates save you from rewriting the same response. Each template has:

- **Name** — your label
- **Body** — up to 350 characters (so it fits Google Play, the stricter limit)
- **Category** — one of: `bug_report`, `feature_request`, `praise`, `complaint`, `general`

### Creating a template

1. Open the **Reply Templates** section above the feed
2. Click **New Template**
3. Fill in name / body / category
4. Save

### Using a template

When you click **Reply** on a review, the template picker appears above the textarea. Pick one to drop its body in — you can still edit before sending.

---

## Syncing

Click **Sync Reviews** at the top of the page to pull the latest reviews from both stores. The sync runs as a background job and the "last synced" timestamp updates when it finishes.

> **Apple star-only reviews:** Apple's API does not return reviews that contain a star rating but no text. If your average rating is moving but no new reviews appear, that's why.

---

## Related

- [Pricing & Plans](/docs/dashboard/pricing-plans) - Compare review monitoring limits
- [Notifications](/docs/dashboard/notifications) - Surface review-related alerts
- [Analytics](/docs/dashboard/analytics) - Long-term rating trends
- [Releases](/docs/dashboard/releases) - Coordinate replies with a release announcement
