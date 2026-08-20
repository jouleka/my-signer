---
title: Keywords & ASO
description: Edit App Store keywords, track rankings, and find new ideas
order: 9
---

# Keywords & ASO

The Keywords page is the App Store Optimisation (ASO) workspace for your iOS apps. You edit the 100-character keyword string per locale, discover new terms to test, and track ranking positions for the keywords you care about.

> **iOS only.** Google Play does not have an equivalent keywords field. Google Play support is planned but not available yet.

---

## The four tabs

Open **Keywords & ASO** from the sidebar (under **Optimize**), pick an iOS app, and you land in a tabbed workspace:

| Tab | Purpose |
|-----|---------|
| **Editor** | Edit the 100-character keywords string for each locale on your store listing |
| **Suggestions** | Pull keyword ideas from Apple's search-suggestion endpoint for a chosen country |
| **Tracking** | Add keywords to track — see the latest rank + popularity per keyword + country |
| **Locale Map** | See how the same keywords map across the locales you publish in |

The workspace is a loop: discover in Suggestions → decide in Editor → measure in Tracking → compare in Locale Map.

---

## Plan limits

| Capability | Free | Pro | Team |
|------------|------|-----|------|
| Keyword editor | Read-only | Editable | Editable |
| Tracked keywords per app | 5 | 50 | 200 |
| Suggestions | ✓ | ✓ | ✓ |
| Rank refresh cadence | Weekly | Daily | Priority daily |
| Popularity metric | — | ✓ | ✓ |
| Apple Search Ads connection | — | ✓ | ✓ |

On Free, the Editor shows your keywords with a lock icon — you can copy them out, but edits go through the upgrade flow. Tracking still works up to 5 keywords per app.

---

## Editor tab

Displays the active keyword string for the locale you select. The 100-character cap matches what Apple enforces in App Store Connect — MySigner shows a live counter and warns before you exceed it. Duplicate detection flags words already covered by your app name or subtitle so you don't waste characters.

Edits save locally. To publish them, push the listing from the [Releases](/docs/dashboard/releases) page.

---

## Suggestions tab

Pick a country, hit **Get Suggestions**, and MySigner queries Apple's search-suggestion endpoint seeded from your current keywords and category. Promising terms can be added to Tracking in one click. Suggestions are available on every plan.

---

## Tracking tab

Add up to your plan limit (5 / 50 / 200) of keywords. For each you'll see:

- **Latest rank** — position 1–228 or "Not in top 250" (see [How rank is tracked](/docs/dashboard/keyword-rank-explained))
- **Popularity** — 1-to-5 dot indicator (see [Keyword popularity](/docs/dashboard/keyword-popularity))
- **Date checked** — when MySigner last refreshed
- A usage bar showing how close you are to the cap

Removing a keyword stops further checks but keeps historical ranks, so re-adding later preserves trend context.

---

## Locale Map tab

If you publish in multiple locales, the Locale Map cross-references your keyword choices — making it obvious when a high-value keyword in one locale isn't yet present in another.

---

## Where to start

1. **Connect Apple Search Ads** *(Pro+)* — required for the Popularity metric. See [Connect Apple Search Ads](/docs/dashboard/connect-apple-search-ads).
2. **Clean up the Editor** for your primary locale — drop anything already in your app name or subtitle.
3. **Add 10–20 candidates** via the Suggestions tab.
4. **Let Tracking refresh** overnight and check back tomorrow.
5. **Iterate** — adjust keywords, push through [Releases](/docs/dashboard/releases), and watch Tracking across versions.

---

## Related

- [Connect Apple Search Ads](/docs/dashboard/connect-apple-search-ads) - Unlock the Popularity metric with OAuth setup
- [Keyword popularity](/docs/dashboard/keyword-popularity) - What the 1-to-5 dot scale means
- [Keyword rank explained](/docs/dashboard/keyword-rank-explained) - How tracking works and why "Not in top 250" appears
- [Releases](/docs/dashboard/releases) - Push edited keywords to the App Store
- [Custom Product Pages](/docs/dashboard/custom-product-pages) - Per-CPP keyword assignments
