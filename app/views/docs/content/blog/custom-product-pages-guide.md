---
title: Custom Product Pages on iOS Explained (and How to Manage All of Them)
description: A practical guide to App Store Custom Product Pages, when they make sense, and how to manage them at scale without losing your mind.
order: 3
---

# Custom Product Pages on iOS: A Practical Guide

The short version: Custom Product Pages let you serve different screenshots and promo text to different audiences on the App Store. Each one connects to an Apple Search Ads campaign so you can see how it converts. Setting them up is easy; managing them at scale is where it gets messy.

If you've heard about Custom Product Pages and weren't sure if they're worth your time, this guide is the practical version. Real numbers, when they help and when they don't, and how to keep a large CPP set manageable.

---

## What Custom Product Pages Actually Are

Apple launched Custom Product Pages (CPPs) with iOS 15 in late 2021. Each CPP is a separate landing page on the App Store with its own:

- **Screenshots** (up to 10, per device size, per locale)
- **App preview videos** (up to 3, per device size, per locale)
- **Promotional text** (up to 170 characters per locale)

Each CPP has a unique URL (`https://apps.apple.com/app/yourapp/id123?ppid=<UUID>`) and a deep link. When someone arrives at your app via that URL, they see your CPP variant instead of the default product page.

Apple lets you create up to **70 CPPs per app** (the limit was raised from 35 in October 2025). Each has its own conversion data in App Store Connect.

What CPPs are not: CPPs do not change your app name, subtitle, icon, or category; those are fixed per app. CPPs also do not change what shows up in App Store search results, and the keyword field is still shared across all your CPPs.

---

## When CPPs Actually Help

CPPs are worth setting up when at least one of these is true:

### 1. You run paid acquisition

Apple Search Ads campaigns can target a specific CPP. Different ad creative drives different keyword searches, and the CPP showing a relevant set of screenshots gets meaningfully better conversion than a generic page.

Published case studies show meaningful CPP lifts when the page is aligned with the ad creative: State of Survival reported a 33% conversion increase after switching, CBS Sports around 20%. Your mileage will vary depending on how distinct your variants are.

### 2. You serve multiple distinct audiences

If your app has two obvious audience segments (students and professionals, say) and each cares about different features, separate CPPs let you show students "study mode" and professionals "report export" without compromising either.

### 3. You run seasonal promotions

Black Friday, end of year, summer travel. A CPP with seasonal screenshots and promo text outperforms editing your main product page for a 30-day window.

### 4. You're A/B testing screenshot variants

A/B testing officially exists in App Store Connect Product Page Optimization, but CPPs combined with Apple Search Ads attribution data are a faster way to see which screenshot set converts better. Send one ad campaign to variant A and another to variant B, then compare conversion rates.

---

## When CPPs Are a Waste

Don't set up CPPs if:

- **You have no paid acquisition.** Organic search results all point to your default product page, not CPPs. Without paid traffic to drive specifically to CPPs, no one sees them.
- **Your audience is one homogeneous group.** A todo list app for "anyone who wants to be productive" doesn't benefit from CPPs the way a fitness app split between runners and lifters does.
- **Your default page already converts well.** If you don't have a problem to solve, you don't need a tool to solve it.

---

## The Management Problem at Scale

Apple now lets you create up to 70 CPPs per app. The real challenge isn't hitting the limit; it's managing the asset explosion that comes with dozens of variants.

For each CPP you maintain:

- Up to 10 screenshots per device size (6.9" iPhone, 13" iPad)
- For up to ~40 locales if you've fully localized
- Plus app preview videos (up to 3 per device size per locale)
- Plus promo text in each locale

A fully-localized 70-CPP setup runs into the tens of thousands of individual assets if you go all-in on localization. Even at 10% localization, that's thousands of files.

App Store Connect's UI for CPPs requires creating each one manually, uploading screenshots one at a time, copy-pasting promo text per locale. At larger scale, a single ASC bug or accidental deletion costs more to recover from.

---

## Managing CPPs with MySigner

MySigner's dashboard treats CPPs as a managed resource. You create a CPP once and:

- **Push screenshots** to it from a Screenshot Studio project (same canvas editor used for your default screenshots)
- **Reuse a base template** across CPP variants; only change the screenshot variants and caption text
- **Translate promo text** automatically across locales with the AI translator (100/month on Pro)
- **Track conversion** per CPP, pulled daily from App Store Connect
- **Wire to Apple Search Ads** campaigns via the campaign URL, with conversion attribution baked in

You stop editing dozens of separate pages in ASC. Instead you edit one shared template and push variants.

---

## Step-by-Step: Setting Up Your First CPP

### 1. Plan your audience

Don't make a CPP just because you can. Pick one audience that you know runs paid acquisition or one seasonal moment. For example: "Students preparing for finals" or "Black Friday 2026."

### 2. Create the CPP in App Store Connect

App Store Connect → your app → **Custom Product Pages** → **Create New Custom Product Page**. Give it a name (internal only, not shown to users). Save.

You'll get the CPP's UUID; keep this, you'll use it to construct the URL.

### 3. Add screenshots, app previews, promo text

Either manually in ASC, or in MySigner: connect your existing Screenshot Studio project, pick the variant images for this audience, click **Push to CPP**.

### 4. Submit the CPP for review

CPPs go through Apple review the same way your main product page does. Usually 1-3 days.

### 5. Wire to an Apple Search Ads campaign

In Apple Search Ads Advanced, edit your campaign → **Custom Product Page** → pick your new CPP. Now everyone who clicks an ad in this campaign sees your variant instead of the default page.

### 6. Watch conversion data

Once you've accumulated a few thousand impressions, you'll have enough data to compare your CPP's conversion rate against the default. Apple Search Ads shows it side by side.

---

## CPP URLs

If you want to share a CPP via deep link, social, or email (not through Apple Search Ads), the URL format is:

```
https://apps.apple.com/<country>/app/<app-slug>/id<numeric-app-id>?ppid=<CPP-UUID>
```

Example:

```
https://apps.apple.com/us/app/pocket-notes/id6443210987?ppid=A1B2C3D4-5E6F-7G8H-9I0J-K1L2M3N4O5P6
```

The `?ppid=` parameter is what tells App Store to show your CPP variant.

---

## Per-Variant Tracking

App Store Connect tracks impressions, page views, and conversion rate per CPP. MySigner pulls that data daily and shows it alongside your default page so you can compare:

| Variant                | Page views | Conversion rate |
| ---------------------- | ---------- | --------------- |
| Default product page   | 12,400     | 3.2%            |
| Students (CPP A)       | 3,800      | 4.7%            |
| Black Friday (CPP B)   | 1,950      | 5.1%            |

If a variant's conversion isn't beating default, archive it. In practice, a handful of CPPs (often 5-10) do the work; the rest either go unused or perform similarly to default.

---

## Common Pitfalls

### Setting up CPPs without paid traffic
Without ads pointing at them, CPPs get almost no impressions. The default page absorbs all your organic traffic.

### Forgetting to localize promo text
The 170-character promotional text shows on the CPP. If it's only in English while your audience is in Germany, conversion drops.

### Treating every CPP like a full localized launch
Most CPPs only need full localization for the top 2-3 markets you're targeting with paid ads. Everywhere else, English (or your app's default language) is fine.

### Not archiving losers
A CPP that's underperforming clutters your reporting. Mark it as hidden so it stops accumulating impressions.

---

## TL;DR

CPPs pay off when you run paid acquisition into distinct audience segments. Without that, skip them. Apple's 70-page limit is technically there but rarely the actual constraint; most successful CPP strategies use 5-10 active variants and archive the rest.

If you're already on MySigner Pro, Custom Product Page management is included. If you're on the Free tier and want to try CPPs, the Pro trial is 14 days, no card.

[Start free → mysigner.dev](https://mysigner.dev/users/sign_up)
