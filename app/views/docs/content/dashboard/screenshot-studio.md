---
title: Screenshot Studio
description: Design and ship App Store and Play Store screenshots without leaving MySigner
order: 8
---

# Screenshot Studio

Screenshot Studio is the canvas-based editor for App Store and Play Store marketing screenshots. You bring source captures, MySigner handles device frames, locale text variants, exports, and direct uploads to App Store Connect or Google Play.

---

## Overview

Each project is a container that targets one platform (iOS, Android, or both) and one or more locales. Inside the project, you create **scenes** — one scene per screenshot slot per device. Scenes share the project's template, device frame, and theme; you can override anything per-scene.

When you're done, you can:

- **Export to disk** as a ZIP at any resolution
- **Upload directly** to App Store Connect, Google Play, or an iOS Custom Product Page

---

## Plan limits

| Capability | Free | Pro | Team |
|------------|------|-----|------|
| Projects per org | 1 | 10 | 30 |
| Scenes per project | 5 | 10 | 15 |
| Media storage (source images, backgrounds, stickers) | 300 MB | 2 GB | 10 GB |
| Export storage (rendered PNGs) | 500 MB | 5 GB | 20 GB |
| Direct store upload | ✗ | ✓ | ✓ |
| Daily store-upload cap | — | 60 | 300 |

When you exceed the project quota (e.g. downgrading from Pro → Free with 8 projects), the **newest projects beyond the limit become read-only** ("plan-frozen") rather than being deleted. The **oldest** projects (within the new limit) stay editable, on the assumption that older projects are the ones still on a release cadence and shouldn't be disrupted.

---

## Creating a Project

1. Go to **Screenshot Studio** in the sidebar
2. Click **New Project**
3. Enter:
   - **Name** — unique within your organization
   - **Platform** — iOS, Android, or both
   - **Template** — one of nine pre-built designs (Sunset Showcase, Geometric Bold, Neon Hero, Warm Editorial, Tech Grid, Value Promise, Feature Showcase, Social Proof, Playful Party)
   - **Locales** — up to 40 from the App Store / Google Play locale list
4. Click **Create**

You're dropped into the editor with an empty scene list.

---

## The Editor

The editor has three panels:

| Panel | Contents |
|-------|----------|
| **Left** | Scene list with thumbnails. Drag to reorder. Add or delete scenes. |
| **Centre** | The canvas — device frame, your screenshot, caption, subtitle, stickers. |
| **Right** | Per-scene controls (caption, subtitle, locale variants, overrides) and per-project settings (template, device frame, background, fonts). |

### Adding scenes

Click **Add Scene** (or drop files into the upload zone). Each upload accepts PNG or JPEG and creates one scene per file. Source images count toward your media-storage quota.

### Device frames

Built-in frames cover:

- **iPhone:** 16 Pro Max, 15 Pro Max, 11 Pro Max, 8 Plus
- **iPad:** Pro 12.9", Pro 11"
- **Android:** Pixel 9, Generic Phone, Generic 7" Tablet, Generic 10" Tablet

You pick the frame at the project level. Scenes can override it.

### Stickers

The sticker library has four sections:

- **Annotations** — arrows, highlights, callouts, numbered badges, checkmarks
- **Icons** — 90+ glyphs covering arrows, status, communication, commerce, charts, devices, social
- **Badges** — Editor's Choice, #1 App, Top Rated, Featured, Staff Pick, etc.
- **UI Elements** — pill badges, star ratings, notification dots, toggles, progress bars

You can also upload your own PNG/JPEG/WebP stickers (max 5 MB each, 50 per project) and a custom background image (max 10 MB).

### Locale variants

Each scene can carry per-locale caption and subtitle overrides via the locale picker in the right panel. If a locale has no override, the project's default text is used.

---

## Exporting

Click **Render Export** to render every scene at the chosen device resolutions in your browser, then **Download** to receive a ZIP. Files are also stored on the server (subject to your export-storage quota) so you can re-upload to a store later without re-rendering.

> **Note:** Each batch upload is capped at 60 files. Large multi-locale exports may need multiple renders.

---

## Uploading to a store

This requires Pro or Team (`store_upload_enabled`).

1. After exporting, click **Upload to Store**
2. Pick a target:
   - **App Store Connect** — requires the App Store version ID and a locale
   - **Google Play** — requires the package name and language
   - **Custom Product Page** — requires the CPP localisation ID
3. Optionally tick **Replace existing** to wipe the current screenshots before uploading
4. Optionally tick **All locales** to push every locale variant in one batch
5. Submit

The upload runs in the background. A progress card appears in the project view showing per-file progress, the current locale, and any errors. You can leave the page — it'll keep going.

> **Daily limit:** 60 uploads per organisation per day on Pro, 300 on Team. Exceeding it blocks new uploads until the rolling 24-hour window passes.

---

## Plan-frozen projects

If your plan no longer covers the number of projects you have, MySigner does **not delete** anything. Instead, the **newest projects beyond your quota** become read-only — the oldest ones (within the limit) stay editable:

- You can still view frozen projects
- You cannot create new scenes in them, edit existing scenes, or trigger uploads
- A "Plan frozen" badge appears in the project list

To unfreeze, either upgrade or delete projects until you're back under the limit.

---

## Related

- [Pricing & Plans](/docs/dashboard/pricing-plans) - Compare plan limits
- [Custom Product Pages](/docs/dashboard/custom-product-pages) - Push studio screenshots to a CPP
- [Releases](/docs/dashboard/releases) - Tie screenshots to a release
- [Credentials](/docs/dashboard/credentials) - ASC and Google Play setup required for uploads
