---
title: Custom Product Pages
description: Manage iOS Custom Product Pages — variants, screenshots, keywords, performance
order: 12
---

# Custom Product Pages

Custom Product Pages (CPPs) are App Store-only landing pages that let you tailor a product page to a specific audience or campaign — different screenshots, promotional text, and keywords from your default page. MySigner gives you full lifecycle management: create, edit, upload screenshots, assign keywords, submit for review, and watch performance.

> **iOS only.** Custom Product Pages are an App Store feature; there's no Google Play equivalent.

---

## Plan requirement

Custom Product Pages require **Pro** or **Team**. Free organisations can see the menu entry but the page redirects with an upgrade prompt.

---

## Versioning model

Each CPP is versioned. A version transitions through these App Store states:

| State | Meaning |
|-------|---------|
| `PREPARE_FOR_SUBMISSION` | Draft — editable, not yet submitted |
| `WAITING_FOR_REVIEW` | Submitted, queued for App Review |
| `IN_REVIEW` | App Review is looking at it |
| `APPROVED` | Approved, not yet live |
| `PUBLISHED` | Live on the App Store |
| `REJECTED` | Rejected by App Review |

You always edit the **draft** version. When you submit, that draft becomes the next published version once Apple approves.

---

## Creating a CPP

1. Go to **Custom Product Pages** in the sidebar
2. Click **New Custom Product Page**
3. Fill in:
   - **App** — pick one of your iOS apps
   - **Name** — your internal label for the variant
   - **Locale** — primary locale (you can add more later)
   - **Promotional text** *(optional)* — the text shown above the description
   - Optionally tick **Copy screenshots from the latest live version** — saves you re-uploading
4. Click **Create**

MySigner calls App Store Connect to create the CPP, stores the remote ID, and triggers a sync to pull back the version and localisation records.

---

## The four tabs

### Overview

Edit the basics for the draft version:

- **Name** and **visibility** (public / hidden)
- **Promotional text** per locale
- **Deep link** per version
- The current submission status

### Screenshots

Manage screenshots per device type. You can:

- See the CPP's existing screenshots side-by-side with the live app's defaults (so you know what will change)
- Upload new screenshots from a project in [Screenshot Studio](/docs/dashboard/screenshot-studio), in the right device sizes
- Tick **Replace existing** to wipe the current set before uploading
- Watch upload progress live — uploads run in the background and update the page

### Keywords

Assign keywords to the CPP localisation:

- Pick from your app's keyword pool
- Add keywords that work specifically for the audience this CPP targets
- Remove keywords you've reconsidered

> **Keyword caveat:** App Store Connect requires the **app's primary listing** to have an approved version on file before you can attach keywords to a CPP localisation. If you get an error here, ship a regular release first.

### Performance

When the CPP has been live long enough to gather data, this tab shows:

- **Impressions** — how many users saw the CPP
- **Downloads** (taps that resulted in a download)
- **Conversion rate** — downloads ÷ impressions

Empty state if no data has come in yet.

---

## Submitting for review

When the draft version is ready, click **Submit for Review**. The version transitions to `WAITING_FOR_REVIEW` and joins the App Review queue. You'll see status transitions reflected in the Overview tab as Apple processes it.

If a submission fails, the error is humanised and shown inline (e.g. "Screenshots are required for the iPhone 6.7-inch device" rather than the raw API error).

---

## Localisations

Add as many locale variants as you need. Each localisation carries its own:

- Promotional text
- Screenshots per device
- Keywords

Other CPP-level fields (name, visibility, deep link) are shared across locales.

---

## Deleting a CPP

Click **Delete** on the CPP page. MySigner calls App Store Connect to delete the remote record, then removes the local copy. This action is destructive — there is no soft delete.

---

## Related

- [Screenshot Studio](/docs/dashboard/screenshot-studio) - Source of screenshots for CPPs
- [Keywords & ASO](/docs/dashboard/keywords) - The keyword pool you draw from
- [Releases](/docs/dashboard/releases) - The base App Store listing
- [Pricing & Plans](/docs/dashboard/pricing-plans) - Pro+ plan requirement
