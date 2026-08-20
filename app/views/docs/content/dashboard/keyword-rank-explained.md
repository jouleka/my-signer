---
title: Keyword rank explained
description: How MySigner tracks App Store rank, what "Not in top 250" means, and why ranks jitter
order: 9.3
---

# Keyword rank explained

Open the Tracking tab in [Keywords & ASO](/docs/dashboard/keywords) and you'll see a **Rank** column for each keyword. This page explains what those numbers represent, where they come from, and how to interpret them.

---

## What rank means here

For a given **keyword** + **country** pair:

> Your app's position in the App Store search results list when someone types that keyword.

Rank **1** means your app is first. Rank **47** means 46 apps appear above you. **"Not in top 250"** means we scanned the full result set and couldn't find you.

Rank is **always per-country**. `photo editor` in the US store and `photo editor` in Germany are different result lists, so they're tracked separately.

---

## Where the data comes from

MySigner polls Apple's public App Store search endpoint — the same one the native App Store app uses. For each keyword + country we run the search and note where your bundle ID appears in the results.

- **It's not manual ranking.** Positions are whatever Apple's algorithm returns at query time.
- **It's undocumented.** Apple doesn't publish the endpoint shape. Occasional format shifts cause a refresh to fail — those show as `—` for a day.
- **It's organic, not paid.** Rank doesn't use the Search Ads API.

---

## "Not in top 250"

Apple's search endpoint returns up to ~228 results per query (the exact cap varies slightly by country). If you're not in that first slice, we can't see your actual rank — it could be 229, it could be 10,000. The UI shows **"Not in top 250"** instead of faking a big number.

What to do:

1. **Check relevance.** If the keyword is already in your 100-character string, name, or subtitle and you're still outside the top 250, it's too competitive for your current metadata.
2. **Work the long tail.** Rather than `calendar`, try `shared family calendar` — easier to rank, more qualified users.
3. **Revisit in 7 days.** Apple's index takes a few days to settle after a push.

---

## Non-personalized results

Real App Store search is **personalized** — Apple ranks partly on the user's download history, country, language, and device type. Two people in the same country at the same moment can see different lists.

MySigner queries from a neutral context: no history, no personalized signals. What you see is a **non-personalized proxy** — the ranking Apple would show a fresh device with no prior downloads in that country. This is what every ASO tool does, and it's the right signal for the discovery question: *"how visible am I to someone who doesn't already know me?"* Existing users will often see you rank higher than the tracker shows. Treat rank as trend data, not ground truth.

---

## Refresh cadence

| Plan | Cadence |
|------|---------|
| Free | Weekly |
| Pro | Daily |
| Team | Priority daily (earlier in the refresh window) |

Refreshes run overnight in your organisation's timezone. The **Date checked** column shows the last successful refresh. A manual refresh per keyword is available from its row menu — useful right after a push. Manual refreshes are rate-limited so they queue rather than fire in parallel.

---

## Why ranks oscillate ±3 positions

Even with perfectly stable metadata, you'll see daily ±3 swings. Sources: Apple re-weighting its index; competing apps pushing new metadata or running ASA campaigns; user behaviour in your country (download velocity, retention, ratings) feeding back into rank; sampling noise between two queries of the same endpoint.

Don't react to a single day's 2-position drop. Use a **7-day moving average** before concluding a change is real.

---

## What to track instead of daily rank

The useful signal is **trend**, not absolute position:

| Useful | Less useful |
|--------|-------------|
| 7- or 30-day moving average | Today vs yesterday |
| Rank improvement after a push | Single-day spikes |
| Median rank across a keyword cluster | Chasing rank 1 for one keyword |

Open the history chart behind each keyword in Tracking to see the 30-day sparkline and push markers — that's where the insight lives.

---

## Related

- [Keywords & ASO](/docs/dashboard/keywords) - The ASO workspace overview
- [Keyword popularity](/docs/dashboard/keyword-popularity) - The 1-to-5 dot scale, separate from rank
- [Connect Apple Search Ads](/docs/dashboard/connect-apple-search-ads) - Required for popularity but not for rank
- [Analytics](/docs/dashboard/analytics) - Correlate rank changes with impressions and downloads
