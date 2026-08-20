---
title: Audit Log
description: Immutable record of sensitive actions across your organization (Team plan)
order: 16
---

# Audit Log

The audit log records sensitive events in your organisation — member changes, credential updates, store pushes, billing actions, sign-ins, SSO configuration changes, and more. Entries are **immutable** and retained for **365 days**, with CSV export for compliance reviews.

> **Team plan only.** Events are recorded for every organisation regardless of plan, but **viewing** the log requires Team. Free and Pro see a paywall page with the upgrade option. This means if you upgrade later, you'll have history to look at — nothing is dropped.

---

## What gets logged

The audit log captures 30+ action types, organised by category:

### Members & invitations

- `member_invited`, `member_added`, `member_role_changed`, `member_removed`
- `invitation_cancelled`, `invitation_accepted`

### API tokens

- `api_token_created`, `api_token_revoked`

### Credentials (App Store Connect)

- `asc_credential_added`, `asc_credential_removed`, `asc_credential_activated`

### Credentials (Google Play)

- `google_play_credential_added`, `google_play_credential_removed`, `google_play_credential_activated`

### Organisation

- `organization_created`, `organization_updated`, `organization_deleted`

### Billing & plan

- `plan_upgraded`, `plan_downgraded`, `trial_expired`
- `billing_portal_accessed`

### Auth & account

- `sign_in_failed`, `password_changed`, `email_changed`

### Stores

- `store_listing_pushed`, `play_store_pushed`, `release_submitted`

### SSO

- `sso_login`, `sso_login_failed`
- `sso_configuration_created`, `sso_configuration_updated`, `sso_configuration_removed`

---

## What each entry contains

| Field | Description |
|-------|-------------|
| Time (UTC) | When it happened |
| Actor | The user who performed the action — or "System" for jobs (trial expiry, retention) |
| Action | One of the action types above |
| Resource type / ID | What it was done to (e.g. `Membership`, `ApiToken`) |
| IP address | Truncated to /24 for IPv4 and /64 for IPv6 to balance forensics with privacy |
| Metadata | A JSON blob with action-specific details (e.g. role change, token name) — click to expand |

---

## Filtering

The page provides four filters:

- **Actor** — pick a member from the dropdown
- **Action** — pick a single action type
- **From** — start date
- **To** — end date

Click **Apply** to filter; **Clear** to reset.

50 events per page, most recent first.

---

## Exporting to CSV

Click **Export CSV** in the header. The download contains the same columns as the table, **filtered to whatever filters you currently have applied**. Useful for:

- Quarterly compliance reviews
- Investigating a specific time range
- Pulling all actions by a single user

The filename follows the pattern `audit_log_{org_id}_{YYYY-MM-DD}.csv`.

> **Spreadsheet-injection defence:** any CSV cell value starting with `=`, `+`, `-`, `@`, tab, or carriage return is prefixed with a single quote. This prevents a malicious actor's name or metadata field from executing as a formula when the CSV is opened in Excel/Sheets. You may see a leading `'` on a few cells — that's the defence in action.

---

## Who can view it

- **Team plan** organisation — gated by the `audit_log_enabled` entitlement
- **Admin or Owner** role — Developers and Viewers can't see it
- The Pundit scope only returns events from organisations where the current user is admin/owner *and* the org is on Team — so even cross-org leakage in a hypothetical future internal rollup is prevented at the policy layer

---

## Immutability

Entries cannot be edited or deleted from the UI or the API. The only way an audit entry leaves the database is through:

- The **365-day retention job** (runs every Sunday at 04:00) which deletes events older than 365 days
- A full organisation deletion (the audit table cascades, but at that point there's no organisation to audit)

Even with admin database access, attempting to update or destroy an audit row raises a `ReadOnlyRecord` error at the model layer.

---

## Why "everyone" is recorded but only Team can see

Audit entries are written from `Audit::Logger.log(...)` for every organisation, on every plan. That way, if you upgrade to Team later, you immediately have history — you don't lose the past month of credential and member changes just because you weren't paying yet.

The plan gate is purely on the **viewing** side. This is a deliberate design decision: forensic value comes from continuity.

---

## Failures don't break user actions

The audit logger is fail-safe. If something goes wrong while writing an entry (database hiccup, validation error), the failure is logged at error level (so it surfaces in your Rails error monitoring) and the user-facing action **succeeds normally**. Audit failures must never block a real business operation.

---

## Related

- [Permissions](/docs/dashboard/permissions) - Who has access to view the audit log
- [SSO](/docs/dashboard/sso) - SSO sign-ins and config changes appear here
- [Pricing & Plans](/docs/dashboard/pricing-plans) - Team plan features
- [Organizations](/docs/dashboard/organizations) - Member changes that are audited
