---
title: 14-Day Pro Trial
description: How the auto-enrolled Pro trial works, when it ends, and how to convert
order: 13
---

# 14-Day Pro Trial

Every new MySigner account gets **14 days of Pro features automatically** — no credit card required. This page explains exactly what you get, when reminders arrive, what happens at expiry, and how to convert to a paid plan.

---

## What you get

When you sign up, your account is upgraded to the **Pro tier** for 14 days. That includes:

- Up to 3 owned organisations
- Store uploads to App Store Connect and Google Play
- Up to 10 screenshot projects with 10 scenes each
- 100 AI translations and 50 AI rewrites per month
- 50 tracked keywords per app, with the editable keyword editor
- Review monitoring for up to 5 apps
- Response templates
- Custom Product Pages
- 90 days of analytics history
- 2 GB media storage and 5 GB export storage

Compare with [Pricing & Plans](/docs/dashboard/pricing-plans) to see Free vs Pro vs Team side-by-side.

> **No card required.** You won't be charged at the end of the trial. If you don't subscribe, your account simply downgrades to Free.

---

## When it starts

The trial begins **automatically** the moment you create your account. There's no button to click and no opt-in step.

You'll see a countdown banner across the dashboard showing how many days are left.

---

## Reminder emails

MySigner sends three reminders so the trial doesn't end without warning:

| When | Subject |
|------|---------|
| 7 days remaining | You're halfway through your MySigner Pro trial — 7 days left |
| 3 days remaining | 3 days left on your MySigner Pro trial |
| 1 day remaining | Last day of your MySigner Pro trial — don't lose access |

If you've already subscribed to Pro or Team before a reminder fires, MySigner skips it.

---

## What happens at expiry

A nightly job at 02:00 (your server's local time) checks for trials whose end time has passed. When yours expires:

- Your `plan_tier` is set to **Free**
- You stay on the same account, with the same data — nothing is deleted
- Features above Free's limits become read-only or hidden behind upgrade prompts
- The expiry is recorded in your organisation's [audit log](/docs/dashboard/audit-log) (Team plan)

If you subscribe to a paid plan during your trial, the trial fields are cleared and you go straight to the paid tier — no double-charging, no wasted trial days.

---

## Converting to paid

To keep Pro (or upgrade to Team) before the trial ends:

1. Go to **Plans & Billing** (sidebar → Account)
2. Pick your tier and billing interval (monthly or yearly)
3. Click **Upgrade**
4. Complete checkout via Paddle

Your subscription kicks in immediately and your trial state is cleared.

---

## What if I deleted my account and re-signed up?

Trial entitlement is tracked per email address using a one-way hash — so re-registering with the same email after deletion **will not** re-issue the trial.

We also normalise the email so common evasion tactics don't work:

- Whitespace and case are ignored: `Alex@Acme.com` and `alex@acme.com` collide
- The plus-tag suffix is stripped: `alex+trial2@acme.com` and `alex@acme.com` collide

If you legitimately need a second trial (acquired company, new role, etc.), reach out to support.

---

## FAQ

**Will I lose my data after the trial ends?**
No. Your apps, certificates, profiles, keystores, store listings, releases, screenshots, and reviews all stay. Some features just become read-only or hit Free-tier limits until you upgrade.

**Can I subscribe before day 14 to lock in a discount?**
Yes. The yearly plans give you roughly 4 months free vs paying month-to-month, and there's no penalty for subscribing early.

**Do CLI commands stop working when the trial ends?**
The CLI is **completely free** on every tier — `mysigner ship`, signing, builds, TestFlight / Play Store uploads. Trial expiry only affects web-app features above Free's limits.

**Can I downgrade later if I subscribe?**
Yes, manage everything from **Plans & Billing → Manage billing**, which opens your Paddle billing portal.

---

## Related

- [Pricing & Plans](/docs/dashboard/pricing-plans) - Full comparison of tiers
- [Audit Log](/docs/dashboard/audit-log) - Where `trial_expired` is recorded (Team)
- [Notifications](/docs/dashboard/notifications) - Other email alerts you can configure
