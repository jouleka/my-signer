---
title: How to Make App Store Screenshots for All Locales Without Losing a Weekend
description: Localized App Store and Play screenshots used to take a weekend in Figma. Here is the fast way using device frames, captions, and AI translation.
order: 2
---

# How to Make App Store Screenshots for All Locales

The short version: design one template with a device frame and a caption layer, then generate per-device variants and translate captions per locale. One step pushes everything to App Store Connect and Google Play.

App Store and Google Play require screenshots in specific sizes per device. As of late 2024, Apple consolidated requirements to a single 6.9" iPhone (1290 × 2796) and 13" iPad (2064 × 2752) set, and the App Store scales these down for smaller devices automatically. Play wants at least two phone screenshots, ideally per locale, plus tablet screenshots if you target tablets.

If you have ten locales and two device sizes, that's twenty individual screenshots. Doing this in Figma by hand is a weekend, and there will still be mistakes (a caption that overflows in German, sizing that's slightly inconsistent between languages). There's a better way.

---

## The Bare Minimum You Need

Per app, per locale, you need:

| Store           | Minimum required             | Recommended count        |
| --------------- | ---------------------------- | ------------------------ |
| App Store (iOS) | 6.9" iPhone, 13" iPad        | 6-10 screenshots         |
| Play Store      | 2 phone screenshots          | 4-8 phone, 2-4 tablet    |
| App previews    | 0 (optional but high CVR)    | 1-3 short videos         |

iOS uses your largest screenshot to scale down to all smaller iPhones, so you don't have to make separate sets for older devices. Apple consolidated requirements to a single 6.9"/13" set in late 2024.

---

## The Bad Way

Open Figma. Find an iPhone mockup. Drag your in-app screenshot onto it. Add a caption layer. Export PNG. Repeat for the next screen. Repeat for tablet. Now duplicate the whole file, translate every caption to your second locale, export everything. Repeat for languages 3 through 10.

You'll be tired and you'll still have mistakes (a caption that overflows in German, a screenshot that's slightly different sizing between languages).

---

## The Better Way: A Reusable Template

Treat screenshots like a design system. One template per "scene" (one tile of the gallery). Each scene has:

- A **background** (solid color, gradient, image)
- A **device frame** (current iPhone, iPad, Pixel, Android tablet)
- A **screenshot** (the actual in-app image you took)
- A **caption** (short headline, 3-7 words)
- An optional **subtitle**

Once your template is right, swapping the screenshot or translating the caption is a 5-second change instead of a half-hour rebuild.

---

## Step-by-Step (Using MySigner's Screenshot Studio)

The fastest implementation of the template approach is the Screenshot Studio in MySigner. Here's the workflow:

### 1. Take real in-app screenshots

Open your app on the simulator or a real device. Take 6-10 screenshots that show your app's actual screens. Don't add device frames or captions yet; just the raw screen content.

For iOS: use the iPhone 17 Pro Max simulator (highest resolution as of 2026). For Android: use Pixel 10 or Pixel 10 Pro.

### 2. Create a Screenshot Studio project

In the MySigner dashboard, go to **Screenshot Studio → New Project**. Pick a template (Warm Editorial, Tech Grid, Neon Hero, etc.) as a starting point. Add your locale list.

The Free tier supports 1 Screenshot Studio project, the Pro tier supports 10.

### 3. Drop in your screenshots

Drag each raw screenshot into a scene. The template handles the device frame and background automatically. Each scene becomes one tile of your final gallery.

### 4. Write the captions in your primary language

Per scene, write a short caption (3-7 words) and an optional subtitle. Think of the caption as the headline for that screen and the subtitle as one line of supporting detail. Keep captions visible at small sizes (the App Store gallery scales them way down), and avoid more than 7 words.

### 5. Translate to other locales

Click **AI translate** and pick the locales you want. The system fills in translated captions automatically. Treat the output as a draft; a native speaker should sanity-check at least the top three locales by traffic before publishing.

Pro includes 100 AI translations per month, which covers a typical 10-scene project across 8-10 locales.

### 6. Push to App Store Connect and Play Console

From the Screenshot Studio dashboard, click **Push to App Store Connect** (or **Push to Play Console**). The Studio uploads every device size for every locale automatically; no manual zip files or drag-and-drop into ASC.

---

## What "Per Locale" Actually Means

You don't have to translate screenshots into every supported language. Localizing screenshots increases install conversion most in countries where your app's primary language isn't widely spoken.

A reasonable priority order for an English-first app:

1. English (en-US, en-GB)
2. Spanish (es-ES, es-MX)
3. German (de-DE)
4. French (fr-FR)
5. Japanese (ja)
6. Brazilian Portuguese (pt-BR)
7. Italian (it)
8. Korean (ko)

Past those, the marginal conversion lift drops off unless you're already big in a specific market.

---

## Common Mistakes

### Captions that don't fit when translated

German is roughly 25-35% longer than English. "Track your habits" becomes "Verfolge deine Gewohnheiten." Design with the longest expected language in mind, not English.

### Different background per locale

Pick a single visual style across all locales. The user is identifying your app by its visual brand; varying backgrounds break that.

### Forgetting subtitles

The caption is the headline. The subtitle is the proof or detail. Both increase conversion vs caption-only, especially on iPad screenshots where you have more visual room.

### Using App Store Connect's built-in screenshot scaler

Apple has a feature that auto-scales your largest screenshot to smaller devices. It works, but the smaller versions can look soft. If conversion matters, generate proper sizes per device.

---

## Validating Before You Push

App Store Connect rejects screenshots that:

- Are the wrong size for the device class
- Contain Apple trademarks (Apple logo, etc.) in obvious ways
- Show fake metrics ("Used by 1M users" when you have 100)
- Show app states not actually possible in the app

Most of these are caught by the Apple review team after upload, not by validation. Test your screenshots on a real iPhone before submitting; what looks fine at desktop size can look misaligned on the actual gallery.

---

## CI Integration

For teams that want releases automated end-to-end, run `mysigner ship appstore` from your release pipeline. Push screenshots from the Studio dashboard before tagging the release, then let the ship command handle the build, sign, upload, and submit. The CLI authenticates with the same `MYSIGNER_API_TOKEN` you use locally; no additional setup.

---

## The Real Time Win

The first time you set up a Screenshot Studio project takes about an hour: pick template, upload screenshots, write captions, translate, review. After that, every release is about 10 minutes:

- Update screenshots if any in-app screens changed
- Tweak captions if the release has new features
- Click translate
- Push

Ten minutes per release, not a weekend.

---

[Try Screenshot Studio free → mysigner.dev](https://mysigner.dev/users/sign_up)
