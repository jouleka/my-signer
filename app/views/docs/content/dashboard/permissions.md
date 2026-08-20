---
title: Permissions
description: The role-based access control matrix for your team (Team plan)
order: 15
---

# Permissions

The **Permissions** page shows exactly which capabilities each role in your organisation has. It's the single source of truth for "who can do what" in MySigner — and it's wired directly to the Pundit authorisation layer, so what you see on the page is what's enforced in the app.

> **Team plan only.** Free and Pro accounts can see the menu entry; the page redirects with an upgrade prompt.

---

## What's on the page

Two cards stacked vertically:

### 1. The matrix

Rows are capabilities, columns are roles. A checkmark means the role can do that thing.

| Capability | Viewer | Developer | Admin | Owner |
|------------|--------|-----------|-------|-------|
| View org data | ✓ | ✓ | ✓ | ✓ |
| Sync from stores | ✗ | ✓ | ✓ | ✓ |
| Edit store listings | ✗ | ✓ | ✓ | ✓ |
| Push to stores | ✗ | ✓ | ✓ | ✓ |
| AI translate / rewrite | ✗ | ✓ | ✓ | ✓ |
| Invite members | ✗ | ✓ * | ✓ | ✓ |
| Create API tokens | ✗ | ✓ ** | ✓ | ✓ |
| Manage credentials | ✗ | ✗ | ✓ | ✓ |
| Change member roles | ✗ | ✗ | ✓ | ✓ |
| Invite admins | ✗ | ✗ | ✓ | ✓ |
| Delete store listings | ✗ | ✗ | ✓ | ✓ |
| View audit log | ✗ | ✗ | ✓ | ✓ |
| Delete organization | ✗ | ✗ | ✗ | ✓ |

\* Developers can invite Developer or Viewer roles only — not Admin.
\*\* Developers can create Read or Write scope tokens only — Admin scope requires Admin or Owner.

### 2. Team roster

Below the matrix, a table of every member in the current organisation:

- Name and email
- Their role (with an Owner badge for the organisation owner)
- Date they joined

Sorted alphabetically by email.

---

## Owner vs Admin vs Developer vs Viewer

- **Owner** — organisation-level status, one per org. Created automatically when you create the organisation. Owner has every Admin permission plus delete-org. **Ownership is currently fixed for the lifetime of the organisation** — there's no in-app Transfer Ownership flow yet (a future release will add one; until then, contact support if reassignment is needed).
- **Admin** — full control of credentials, roles, and audit log. Cannot delete the org.
- **Developer** — ships builds, edits listings, manages app resources. Limited to inviting Developer/Viewer and creating Read/Write tokens.
- **Viewer** — read-only across the organisation.

For more on assigning roles, see [Organizations](/docs/dashboard/organizations) and the [Team Setup guide](/docs/guides/team-setup).

---

## How the matrix stays accurate

The matrix isn't a static document — it's generated from the same data structure that drives Pundit policies. A test sweeps every (capability × role) pair on every CI run and asserts the matrix value matches what the policy actually allows. When a policy changes, the matrix has to change with it (or the build fails).

Translation: if you see a checkmark on the page, the corresponding action **will** succeed for that role. If you see an ✗, the policy will refuse it.

---

## Read-only today, editable later

The page is **view-only** — you can't change a role's capabilities from here. To change *who has* a role, use the team management UI on the [Organization](/docs/dashboard/organizations) page.

A future release will add per-role custom permission editing. The current matrix gives you a clear, audit-friendly view of the existing role model.

---

## Plan requirement and access

- Team plan only — gated by the `rbac_enabled` entitlement
- Any member of a Team-plan organisation can view the matrix and roster (it's informational, not sensitive)

If you're on Free or Pro and click **Permissions** in the sidebar, MySigner shows the same paywall page used for Audit Log and SSO with a link to upgrade.

---

## Related

- [Organizations](/docs/dashboard/organizations) - Assign roles and manage members
- [Team Setup](/docs/guides/team-setup) - How to invite members and pick roles
- [Audit Log](/docs/dashboard/audit-log) - See *who actually did what*, not just *who could*
- [Pricing & Plans](/docs/dashboard/pricing-plans) - Team plan features
