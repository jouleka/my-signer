---
title: Keyword popularity
description: What the 1-to-5 dot scale means, where the data comes from, and why only some keywords are scored
order: 9.2
---

# Keyword popularity

Next to each tracked keyword on the [Keywords & ASO](/docs/dashboard/keywords) page, MySigner shows a row of 1 to 5 dots. That's the **popularity score** — roughly, how often people actually search that term on the App Store.

---

## The dot scale

Apple returns an integer between 5 and 100. We bucket it into 5 tiers so it's easy to scan:

| Dots | Raw score | Interpretation |
|------|-----------|----------------|
| 1 dot | 5 – 20 | Rarely searched — niche or long-tail |
| 2 dots | 21 – 40 | Low search volume |
| 3 dots | 41 – 60 | Moderate — typical mid-tier term |
| 4 dots | 61 – 80 | Popular — high-value target |
| 5 dots | 81 – 100 | Very popular — competitive, high-volume |

Hover a dot row to see the raw integer in a tooltip.

> **Relative, not absolute.** Apple doesn't publish raw search-volume counts. A score of 80 doesn't mean "80,000 searches/day" — it means "this keyword sits in the 80th tier of Apple's observed popularity distribution." Use scores to compare keywords against each other, not to forecast install volume.

---

## Where the data comes from

Popularity comes from the **Apple Search Ads API**. See [Connect Apple Search Ads](/docs/dashboard/connect-apple-search-ads) for the one-time setup.

Apple only returns popularity for keywords its recommendation engine considers **relevant to your app** — based on your name, subtitle, keywords, category, and historical search behaviour.

Because Apple's API doesn't accept arbitrary queries, we can't ask for the popularity of `photo editor` in the abstract — only for terms Apple already associates with your app. If you add a keyword Apple doesn't consider relevant yet, the popularity column shows `—` (dash) until the recommender picks it up. That usually happens after you push a release containing the term.

---

## Getting more keywords scored

If a tracked keyword shows a dash:

1. **Add it to your 100-character keyword string** (Editor tab) and push the listing — strongest signal to Apple's recommender.
2. **Mention the theme in your description.** Apple reads metadata holistically.
3. **Wait 24–72 hours after a push.** The recommender re-runs periodically, not instantly.
4. **Check the Search Ads connection is active.** A dropped connection stalls all scoring.

There's no way to force Apple to score a truly unrelated keyword. If your app is a calculator and you're tracking `chess puzzles`, popularity will stay blank — and that's the correct signal.

---

## Refresh cadence

| Plan | Cadence |
|------|---------|
| Free | Weekly |
| Pro | Daily |
| Team | Priority daily |

Refreshes run overnight in your organisation's timezone. The **Date checked** column in Tracking shows the last successful refresh per keyword.

---

## Degraded-state warning

Occasionally an amber banner appears on the Keywords page:

> **Popularity data may be degraded** — Apple's Search Ads API is rate-limiting us or returning partial results. Existing scores are still accurate; new scores may be missing or delayed.

This has happened a handful of times since Apple tightened API quotas in October 2025. Existing scores stay valid, rank tracking is unaffected, and we retry automatically with exponential backoff — the banner clears as soon as refresh jobs succeed again.

---

## Reading popularity well

- **Don't chase 5-dot keywords blindly.** High popularity means high competition. A 2-dot keyword where you rank 3 usually beats a 5-dot keyword where you rank 180.
- **Pair popularity with rank.** The best targets are high-popularity keywords where you already rank in the top 20.
- **Popularity shifts over time.** Seasonal terms (`tax calculator`, `valentine cards`) swing dramatically — track the 30-day trend, not a single day.

---

## Related

- [Keywords & ASO](/docs/dashboard/keywords) - The ASO workspace overview
- [Connect Apple Search Ads](/docs/dashboard/connect-apple-search-ads) - One-time setup required for popularity
- [Keyword rank explained](/docs/dashboard/keyword-rank-explained) - How position tracking works
- [Analytics](/docs/dashboard/analytics) - Tie keyword changes back to impressions and installs
