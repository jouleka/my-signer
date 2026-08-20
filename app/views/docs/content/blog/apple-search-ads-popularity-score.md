---
title: Apple Search Ads Popularity Score, Explained for ASO
description: What the Apple Search Ads popularity score actually means, how to use it for ASO keyword research, and how it compares to third-party ASO scores.
order: 8
---

# Apple Search Ads Popularity Score, Explained

**Short version:** The popularity score is a 0-100 value Apple shows inside Apple Search Ads when you research keywords. Higher means more search traffic in that country. It's the only Apple-sourced keyword volume signal that exists, and it's the right anchor for picking what goes in your 100-character iOS keyword field. Caveats and how to use it below.

The Apple Search Ads popularity score (sometimes called "Search Popularity") is one of those features that's easy to miss but disproportionately useful once you find it. Every ASO tool either tries to replicate it (with worse data) or uses it directly.

This article is for ASO practitioners and indie devs who want to use it without doing a six-hour deep dive.

---

## What the Number Actually Is

In the Apple Search Ads campaign creation flow (or the Keyword Planner inside Apple Search Ads Advanced), you'll see a "Popularity" column next to each keyword. The score is on a 0-100 scale and is country-specific.

A few things to know:

- **It's relative, not absolute.** A keyword with popularity 80 in the US has more search volume than a keyword with popularity 50 in the US. But popularity 80 in the US and popularity 80 in Germany are different absolute volumes (the US App Store is larger).
- **It's calibrated to recent App Store searches.** Apple uses real search data from the App Store to derive the number, then bucketed and obfuscated for privacy.
- **It updates regularly.** The number can shift week-over-week as search trends change, especially for trending topics.
- **It's the only Apple-sourced signal.** Third-party ASO tools (Sensor Tower, Asodesk, AppTweak) have their own popularity scores derived from various data sources, but Apple's is the closest to ground truth because it's drawn from actual store searches.

---

## How to Read the Scale

Roughly:

| Popularity | What it means                                        |
| ---------- | ---------------------------------------------------- |
| 0-10       | Very low traffic. Probably not worth a slot.         |
| 10-30      | Low. Worth it for hyper-specific niches or branded.  |
| 30-50      | Moderate. The bulk of indie-app keyword targets.     |
| 50-70      | High. Competitive; you need a strong listing to rank.|
| 70-90      | Very high. Top-tier; usually owned by big apps.      |
| 90-100     | Generic, massive. Hard to crack unless you're huge.  |

For a typical indie app, your sweet spot is keywords in the 30-60 range. High enough to bring meaningful traffic, low enough that you can actually rank.

---

## How to Find the Popularity Score

You need an Apple Search Ads account (free to set up).

1. Sign in at [searchads.apple.com](https://searchads.apple.com).
2. Set up a campaign in your country.
3. Open the Keyword Planner inside the campaign builder.
4. Type a keyword. The popularity score appears next to it.

That's the canonical source.

Most third-party ASO tools surface Apple's popularity score directly inside their UI so you don't have to log in to Apple Search Ads separately:

- **AppTweak** shows it inline in their keyword research view.
- **Asodesk** shows Apple's score alongside their own.
- **MySigner** shows Apple Search Ads popularity scores in the keyword editor, so you see them as you edit your 100-character keyword field per locale.
- **Sensor Tower** historically blended this with their own panel data; check the latest UI for the current behavior.

If you're paying for an ASO tool, look for a column labeled "Search Popularity" or "Apple Popularity"; that's the Apple number.

---

## How to Use It in Your 100-Character Keyword Field

Apple gives you 100 characters of keywords per locale (the field is separate from the app subtitle and app name, both of which also count for ranking). Strategy:

1. **List 30-50 candidate keywords** that are relevant to your app. Brainstorm or import from a competitor's keyword field (visible via reverse-engineering tools).
2. **Get the popularity score for each candidate** in your target country.
3. **Sort by popularity.** Drop everything under ~10 unless it's a high-intent niche term.
4. **Combine words.** Apple matches on individual words plus the app name/subtitle, not on multi-word phrases. So `"notes,fast,minimal,offline,sync"` (commas separate) is read by Apple as the set of individual words, and Apple combines them with your title at search time. You don't need to repeat words that appear in your app name or subtitle.
5. **Fill 100 characters.** Use commas, no spaces (Apple ignores spaces). Example: `notes,sync,markdown,offline,fast,minimal,capture,quick,journal,memo`
6. **Localize per market.** The 100-char field is per-locale. Use the popularity score for each target country to pick locale-specific keywords.

---

## Common Mistakes

### Picking only high-popularity keywords

Popularity 90+ keywords are owned by huge apps. If your app has a 4.2 rating and 5,000 reviews, you won't rank #1 for "music" or "fitness" no matter how good your ASO is. Pick keywords you can plausibly rank for.

### Ignoring relevance

Apple's algorithm checks relevance, not just keyword inclusion. Stuffing "fitness" into your notes-app keyword field won't help you rank; it might hurt you.

### Stuffing high-popularity keywords your competitor owns

"Notes" might be popularity 70 but owned by Apple Notes and Notion. Look at the top 10 ranking apps for the keyword. If they're all 50K+ review giants, pick a different angle.

### Skipping locale-specific research

The popularity score in the US doesn't translate to Germany or Japan. If you're shipping internationally, get the score for each target country and rebuild your keyword set.

### Overweighting third-party popularity scores

Sensor Tower's popularity score is derived from their panel; Asodesk's is derived from theirs. They don't always match Apple's score for the same keyword. Apple's number is the closest to what the algorithm actually uses, so when scores disagree, trust Apple.

---

## The Word-Combination Trick

Apple combines your keyword field words with your app name and subtitle. So you don't need to repeat:

- Words in your app name (e.g., if your app is "Pocket Notes," don't put "notes" in the keyword field; it's already there via the name)
- Words in your subtitle (30 characters)

This frees up keyword slots for terms you're not using elsewhere. Run your app through a keyword density tool to make sure you're not wasting 100-character field space on repeats.

---

## Tracking Your Rankings Over Time

The popularity score tells you what's worth targeting. Tracking tells you whether your bet worked.

For each keyword you target, track your daily rank in your top 3-5 countries. Most ASO tools do this:

- **AppTweak**, **Asodesk**, **Sensor Tower** all offer daily rank tracking.
- **MySigner** tracks 100 keywords per app on Pro (200 on Team), refreshed daily.

What to look for:

- A new keyword you targeted moves from "not ranking" to top 50, then top 20: that's working.
- Your existing keywords drop after a release: your ASO changed for the worse, revisit.
- Seasonal spikes in popularity for related keywords: opportunity to update your keyword field temporarily.

---

## When the Popularity Score Lies

A few cases to watch for:

### Brand searches

"Spotify" has high popularity but it's almost all branded search for one app. Targeting brand terms for competitors won't help you unless you're a direct alternative.

### One-off viral terms

A viral TikTok trend can spike a keyword's popularity for a week, then drop. Don't restructure your whole keyword field around a 1-week spike.

### Misspellings

Apple's popularity score sometimes groups misspellings into the canonical form. So your "popularity 50" keyword might be 30% misspellings.

### Restricted categories

Some categories (medical, financial, kids) have keyword restrictions that override the popularity score's apparent value. Read Apple's content guidelines before betting on a high-popularity keyword in those categories.

---

## TL;DR

The Apple Search Ads popularity score is your best signal for what keywords are worth targeting in ASO. Use it to pick candidates (sweet spot ~30-60 for indies), localize per country, combine cleverly with your app name and subtitle, and track ranks over time. Trust Apple's number over third-party scores when they disagree.

If you want this baked into the keyword editor you use to update your iOS keyword field, MySigner Pro shows Apple Search Ads popularity scores inline. Free trial, 14 days, no card.

[Start free → mysigner.dev](https://mysigner.dev/users/sign_up)
