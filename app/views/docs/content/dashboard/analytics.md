---
title: Analytics
description: Acquisition, engagement, and quality metrics from the App Store and Google Play
order: 11
---

# Analytics

The Analytics dashboard pulls daily snapshots from App Store Connect Analytics and Google Play and rolls them up into a single view across all your apps. Filter by app and date range, and see how the current period compares to the previous one.

---

## Overview

The hero row shows four KPIs at the top:

- **Downloads**
- **Revenue**
- **Crash Rate**
- **Retention D1**

Each KPI shows the current-period total and the percent change versus the previous period of the same length.

Below the hero, the dashboard breaks metrics into categories:

| Category | Metrics |
|----------|---------|
| **Acquisition** | First-time downloads, redownloads, total downloads, impressions, product page views |
| **Engagement** | Updates, sessions, active devices |
| **Stability** | Crashes, crash rate, ANR rate (Android) |
| **Conversion** | Conversion rate (impression → install) |
| **Retention** | Day 1, Day 7, Day 14, Day 28 |
| **Monetisation** | New subscriptions, churned subscriptions, trial starts, trial conversions, proceeds |
| **Android-specific** | Installs, deletions |

---

## Plan limits

The dashboard itself is enabled on every tier. The cap is on **how far back you can look**:

| Tier | Max history window |
|------|--------------------|
| Free | 7 days |
| Pro | 90 days |
| Team | 365 days |

The date-range buttons (7d / 14d / 30d / 90d / 365d) are disabled for any range beyond your plan's window. If you've recently downgraded, the page handles a missing previous period gracefully — you'll see the current period without a percent-change comparison.

---

## Filtering

Two filters at the top of the page:

- **App** — All apps, or a single Apple/Android app
- **Date range** — 7d, 14d, 30d, 90d, 365d (subject to your plan's history cap)

Both apply to every metric on the page.

---

## How fresh is the data?

Click **Sync** to enqueue a background job that pulls the latest snapshots. The "last synced" timestamp at the top of the page tells you when the most recent snapshot landed. The sync also runs on a schedule, so the manual button is mostly for "I want to see a metric *right now*" cases.

> **Note on reporting lag:** App Store Connect and Google Play themselves have a one- to two-day reporting lag. Yesterday's data may not be there yet — that's the source, not MySigner.

---

## Reading the percent change

Each metric in a category card shows:

- The total (sum) or average for the current period
- A percent change vs. the previous period of the same length

Crash and ANR rates are stored as decimals (e.g. `0.001` = `0.1%`) and rendered as percentages.

If the previous period falls partly outside your plan's history window, MySigner labels the comparison as truncated rather than computing a misleading delta.

---

## Empty state

If MySigner has no snapshots for the selected app and range yet, the dashboard shows an empty state pointing you to **Sync**. This is normal:

- Right after connecting credentials
- For brand-new apps with no traffic
- If a sync is still in flight

---

## Related

- [Credentials](/docs/dashboard/credentials) - Required for analytics sync
- [Reviews & Ratings](/docs/dashboard/reviews) - Sentiment alongside acquisition
- [Keywords & ASO](/docs/dashboard/keywords) - See whether keyword changes lifted impressions
- [Pricing & Plans](/docs/dashboard/pricing-plans) - History-window limits per tier
