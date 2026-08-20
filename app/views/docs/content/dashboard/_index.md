---
title: Dashboard
description: Web dashboard documentation for managing your apps and team
order: 1
---

# Dashboard

The MySigner Dashboard is your web-based control center for managing iOS and Android app signing, store releases, ASO, team collaboration, and billing.

---

## Getting Started

<div class="grid gap-4 md:grid-cols-2">

### [Organizations](/docs/dashboard/organizations)
Create and manage organizations, invite team members, and assign roles.

### [Credentials](/docs/dashboard/credentials)
Set up App Store Connect and Google Play credentials.

### [API Tokens](/docs/dashboard/api-tokens)
Generate tokens for CLI authentication and CI/CD pipelines.

### [Notifications](/docs/dashboard/notifications)
Configure email alerts for expiry, sync, revocations, and team activity.

</div>

---

## Signing Resources

| Platform | Documentation |
|----------|---------------|
| [iOS Resources](/docs/dashboard/ios-resources) | Certificates, provisioning profiles, devices, bundle IDs |
| [Android Resources](/docs/dashboard/android-resources) | Keystores, apps, tracks |

---

## Publish

### [Releases](/docs/dashboard/releases)
Configure store listings, release notes, AI translation/rewrite, the review workflow, release checklists, and phased rollouts.

### [Screenshot Studio](/docs/dashboard/screenshot-studio)
Design App Store and Play Store screenshots in the canvas editor and push them straight to ASC, Google Play, or a Custom Product Page.

---

## Optimise *(Pro+)*

<div class="grid gap-4 md:grid-cols-2">

### [Keywords & ASO](/docs/dashboard/keywords)
Edit App Store keywords per locale, track rankings, and find new ideas.

### [Reviews & Ratings](/docs/dashboard/reviews)
A unified inbox for App Store and Google Play reviews — filter, reply, and use response templates.

### [Analytics](/docs/dashboard/analytics)
Acquisition, engagement, stability, retention, and monetisation metrics.

### [Custom Product Pages](/docs/dashboard/custom-product-pages)
Create iOS Custom Product Pages with their own screenshots, keywords, and promotional text.

</div>

---

## Billing

### [14-Day Pro Trial](/docs/dashboard/trial)
How the auto-enrolled Pro trial works, when it ends, and how to convert.

### [Pricing & Plans](/docs/dashboard/pricing-plans)
Free, Pro, and Team — full feature comparison, limits, and how to upgrade.

---

## Team Plan Features

<div class="grid gap-4 md:grid-cols-2">

### [Audit Log](/docs/dashboard/audit-log)
Immutable record of sensitive actions across your organisation, with CSV export and 365-day retention.

### [Permissions](/docs/dashboard/permissions)
Role-based access control matrix — see exactly which capabilities each role has.

### [SSO (SAML 2.0)](/docs/dashboard/sso)
Single Sign-On with Okta, Microsoft Entra ID, Google Workspace, or any SAML 2.0 IdP.

</div>

---

## Quick Overview

### Organizations

Organizations are the top-level container in MySigner. Each organization has:

- **Members** in three assignable roles (Admin, Developer, Viewer) plus an **Owner** organisation-level status
- **Credentials** for App Store Connect and Google Play
- **Resources** like certificates, profiles, keystores
- **Apps** synced from the app stores

### Navigation

The dashboard sidebar is grouped into six sections:

| Section | Items |
|---------|-------|
| **Overview** | Dashboard |
| **Publish** | Screenshot Studio, Releases |
| **Optimize** *(Pro+)* | Keywords & ASO, Reviews & Ratings, Analytics, Custom Product Pages |
| **Manage** | Signing & Assets (certificates, profiles, devices, bundle IDs, keystores, apps) |
| **Automate** | CLI & Docs (Quickstart, Commands, Guides, Dashboard), API Tokens |
| **Account** | Organizations, Plans & Billing, Audit Log *(Team)*, Permissions *(Team)*, SSO *(Team)*, Settings |

The top nav also exposes an organization switcher, a Command Palette (`⌘K` / `Ctrl+K`), unified Sync (iOS / Android), notifications, and your account menu.

### Syncing Data

MySigner syncs with App Store Connect and Google Play to fetch your apps, certificates, profiles, and more. You can trigger a sync manually:

1. Go to your organization page
2. Click **Sync** for iOS or Android
3. Wait for the sync to complete

Manual sync is available on every plan. The dashboard also runs recurring background syncs on every plan — cadence scales with your tier (see [Pricing & Plans](/docs/dashboard/pricing-plans) for the per-tier breakdown).

---

## Related

- [Getting Started](/docs/quickstart/getting-started) - Initial setup guide
- [CLI Commands](/docs/commands) - Command-line reference
- [Guides](/docs/guides) - Step-by-step tutorials
