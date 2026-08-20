---
title: Pricing & Plans
description: Free, Pro, and Team — feature comparison, limits, and how to upgrade
order: 14
---

# Pricing & Plans

MySigner has three tiers: **Free**, **Pro** ($12/mo), and **Team** ($49/mo). The CLI is completely free on every tier. Plan limits apply to the web app: how many apps you can manage, how often you can push to stores, how much you can use AI, and which collaboration features unlock.

---

## Pricing

| Tier | Monthly | Yearly | Save |
|------|---------|--------|------|
| Free | $0 | $0 | — |
| **Pro** | **$12/mo** | **$96/yr** (~4 months free) | 33% |
| **Team** | **$49/mo** | **$390/yr** (~4 months free) | 34% |

You toggle between Monthly and Yearly billing on the Pricing page; pick whichever interval makes sense for you.

---

## Who each tier is for

- **Free** — solo developers shipping a single app, validating MySigner end-to-end.
- **Pro** — individual builders shipping regularly with store uploads and AI assistance.
- **Team** — agencies and multi-app operations that need seats, audit logs, RBAC, and SSO.

---

## Feature comparison

### Organisations & seats

| | Free | Pro | Team |
|---|------|-----|------|
| Owned organisations | 1 | 3 | 10 |
| Seats per organisation | 1 | 1 | **10** |

> Pro is **single-seat** — same as Free. If you need teammates, that's Team. Pro is intentionally for solo developers shipping multiple apps.

### CLI

| | Free | Pro | Team |
|---|------|-----|------|
| `mysigner ship` (TestFlight + Play Store) | ✓ | ✓ | ✓ |
| `mysigner sync`, `doctor`, `validate` | ✓ | ✓ | ✓ |
| All other CLI commands | ✓ | ✓ | ✓ |

The CLI has zero plan gates. Every feature on every tier — that's the acquisition hook for the whole product.

### Sync & store push

| | Free | Pro | Team |
|---|------|-----|------|
| Manual sync (App Store Connect / Google Play) | ✓ | ✓ | ✓ |
| Store sync cadence (ASC / Google Play) | Daily | Every 6h | Every 3h |
| Review sync cadence | Daily | Every 2h | Every 30 min |
| Analytics sync cadence | Weekly | Daily | Daily |
| Push store listings to ASC / Google Play | ✗ | ✓ | ✓ |
| Daily store-upload cap (per org) | — | 60 | 300 |

### Store listings

| | Free | Pro | Team |
|---|------|-----|------|
| Store-listing apps | 1 | 999 | 999 |
| Locales per app | 1 | 10 | unlimited |

### Screenshot Studio

| | Free | Pro | Team |
|---|------|-----|------|
| Projects per org | 1 | 10 | 30 |
| Scenes per project | 5 | 10 | 15 |
| Media storage | 300 MB | 2 GB | 10 GB |
| Export storage | 500 MB | 5 GB | 20 GB |

### AI translate / rewrite (per month)

| | Free | Pro | Team |
|---|------|-----|------|
| AI translations | 5 | 100 | 500 |
| AI rewrites | 3 | 50 | 200 |

Quotas reset on the 1st of each calendar month.

### ASO (Keywords / Reviews / Analytics / CPPs)

| | Free | Pro | Team |
|---|------|-----|------|
| Tracked keywords per app | 5 | 50 | 200 |
| Keyword editor | Read-only | Editable | Editable |
| Review monitoring (apps) | 1 | 5 | 999 |
| Response templates | ✗ | ✓ | ✓ |
| Custom Product Pages | ✗ | ✓ | ✓ |
| Analytics history | 7 days | 90 days | 365 days |

### Releases

| | Free | Pro | Team |
|---|------|-----|------|
| Release checklist | Read-only | Editable + custom items | Editable + custom items |
| Release notes history | ✓ | ✓ | ✓ |

### Team-tier exclusives

| | Free | Pro | Team |
|---|------|-----|------|
| Audit Log | ✗ | ✗ | ✓ (365-day retention) |
| Permissions matrix (RBAC) | ✗ | ✗ | ✓ |
| SAML 2.0 SSO | ✗ | ✗ | ✓ |

---

## The 14-day Pro trial

Every new account gets **14 days of Pro automatically**, no card required. See [14-Day Pro Trial](/docs/dashboard/trial) for the full details.

---

## Upgrading

1. Go to **Plans & Billing** in the sidebar (Account section)
2. Pick your billing interval — Monthly or Yearly
3. Click **Upgrade** on the tier you want
4. A preview modal opens showing the change summary
5. Confirm to launch Paddle Checkout
6. Complete payment

Your new tier kicks in immediately and any active trial fields are cleared.

If you're already subscribed and want to switch from Monthly to Yearly (cheaper) or up/down a tier, the same flow handles it — the preview shows what you'll be charged and when.

---

## Managing your subscription

Click **Manage billing** on the Pricing page (visible when you have an active subscription). This opens your **Paddle billing portal** in a new tab where you can:

- Update your payment method
- Download invoices
- Cancel your subscription
- Schedule a downgrade at next renewal

Cancellation does not delete your data — your account simply downgrades to Free at the end of the current billing period.

---

## What happens if I downgrade?

Nothing is deleted. Features above Free's limits become read-only or hidden behind upgrade prompts:

- Extra organisations / projects / locales remain visible but become **plan-frozen** (read-only)
- AI quotas drop to Free's limits at the start of the next month
- Audit log entries are still recorded but the page is hidden until you re-upgrade

---

## Related

- [14-Day Pro Trial](/docs/dashboard/trial) - How the auto-trial works
- [Audit Log](/docs/dashboard/audit-log) - Team-tier feature
- [Permissions](/docs/dashboard/permissions) - Team-tier RBAC matrix
- [SSO](/docs/dashboard/sso) - Team-tier SAML 2.0
- [Organizations](/docs/dashboard/organizations) - Member roles and ownership
