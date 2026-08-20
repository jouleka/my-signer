---
title: Team Setup
description: Set up your organization with team members and roles
order: 8
---

# Team Setup

This guide walks you through setting up your organization with multiple team members, managing roles, and configuring access control.

> **Plan check first.** Multi-seat collaboration requires the **Team** plan. Free and Pro are both **single-seat** (1 member per organisation). If you signed up recently, you're on a 14-day [Pro trial](/docs/dashboard/trial) — but to actually invite teammates you need to upgrade to Team. See [Pricing & Plans](/docs/dashboard/pricing-plans) for the seat limits per tier.

---

## Overview

MySigner organizations allow teams to:

- **Share credentials** - App Store Connect and Google Play credentials are shared with the team
- **Manage resources** - Certificates, profiles, keystores, and apps are organization-wide
- **Control access** - Role-based permissions for members (full matrix at [Permissions](/docs/dashboard/permissions))
- **Collaborate** - Multiple people can ship builds without sharing personal tokens
- **Track sensitive actions** - Every membership / credential / billing change is recorded in the [Audit Log](/docs/dashboard/audit-log) (Team)
- **Centralise authentication** - Optional [SAML 2.0 SSO](/docs/dashboard/sso) with Okta, Microsoft Entra, Google Workspace, or any generic IdP (Team)

---

## Step 1: Create an Organization

If you haven't already, create an organization:

1. Go to the **MySigner dashboard**
2. Click **New Organization** in the sidebar
3. Enter a name (e.g., "Acme Inc" or "Mobile Team")
4. Click **Create Organization**

You're automatically assigned as the **Owner** of the organization. *(Owner is an organisation-level status, not one of the assignable roles — see [Step 3](#step-3-understand-roles).)*

> **Plan note:** The number of organizations you can own depends on your plan (Free: 1, Pro: 3, Team: 10). If creation is blocked, MySigner shows an upgrade prompt instead of silently failing.

---

## Step 2: Invite Team Members

### Send Invitations

1. Go to **Organization Settings** → **Team**
2. Click **Invite Member**
3. Enter their email address
4. Select their role (Admin, Developer, or Viewer)
5. Click **Send Invitation**

> **Note:** Developers can only invite other Developers or Viewers. Only Admins and Owners can invite Admins.

> **Plan note:** Seat capacity is **1** on Free and Pro and **10** on Team. The invitation flow refuses with an upgrade prompt when you exceed the seat limit.

The invitee receives an email with a link to join.

### Invitation States

| Status | Description |
|--------|-------------|
| Pending | Invitation sent, awaiting response |
| Accepted | Member joined the organization |
| Expired | Invitation not accepted within 7 days |

---

## Step 3: Understand Roles

MySigner has three assignable **roles** (Admin, Developer, Viewer) plus a special **Owner** status that belongs to one user per organization.

> **Owner is not a selectable role.** When you create an organization you become its Owner automatically. Ownership is a separate organization-level status — every Owner also has a membership row, and the Owner-status grants the same permissions as Admin plus the ability to delete the organization. **Ownership is currently permanent for the lifetime of the organisation** — there's no in-app Transfer Ownership flow yet (contact support if you need to reassign). The role dropdown when inviting only shows Admin, Developer, and Viewer.

### Owner *(organization-level status, one per org)*

- Full access to everything Admin has, plus:
- Can delete the organization
- Cannot currently be changed in-app — ownership is fixed for the lifetime of the organisation (contact support if reassignment is needed)
- Cannot be removed from the team like a regular member

### Admin *(role)*

- Manage team members (invite any role, remove, change roles)
- Manage credentials (add, edit, delete)
- Manage all resources (keystores, devices, profiles)
- Cannot delete organization

### Developer *(role)*

- Ship builds and trigger syncs
- Manage app resources (releases, app config)
- Create API tokens (Read or Write scope only — **Admin scope requires Admin or Owner**; see the [Permissions matrix](/docs/dashboard/permissions) for the full role-vs-scope rules)
- Invite new members (Developer or Viewer roles only)
- View credentials (sensitive values hidden)
- Cannot manage credentials, keystores, or devices

### Viewer *(role)*

- View all resources (read-only)
- View credentials (sensitive values hidden)
- Cannot ship builds, create tokens, or make changes

### Role Comparison

| Capability | Owner | Admin | Developer | Viewer |
|------------|-------|-------|-----------|--------|
| View resources | ✓ | ✓ | ✓ | ✓ |
| Ship builds | ✓ | ✓ | ✓ | ✗ |
| Trigger sync | ✓ | ✓ | ✓ | ✗ |
| Manage releases | ✓ | ✓ | ✓ | ✗ |
| Create API tokens | ✓ | ✓ | ✓ | ✗ |
| Invite members | ✓ | ✓ | ✓* | ✗ |
| Manage devices | ✓ | ✓ | ✗ | ✗ |
| Manage profiles | ✓ | ✓ | ✗ | ✗ |
| Manage keystores | ✓ | ✓ | ✗ | ✗ |
| Manage credentials | ✓ | ✓ | ✗ | ✗ |
| Remove members | ✓ | ✓ | ✗ | ✗ |
| Change roles | ✓ | ✓ | ✗ | ✗ |
| Delete organization | ✓ | ✗ | ✗ | ✗ |

*Developers can only invite Developer or Viewer roles, not Admin.

> **Transfer Ownership is not yet available in-app.** The Owner is fixed for the lifetime of the organisation. A self-service Transfer Ownership flow is on the roadmap; until then, contact support if you need to reassign.

---

## Step 4: Configure API Tokens

Each team member should create their own API token:

### Personal Tokens

1. Go to **API Tokens** in the sidebar
2. Click **Create Token**
3. Name it descriptively (e.g., "MacBook Pro - John")
4. Copy and store securely

### CI/CD Tokens

Create dedicated tokens for CI/CD systems:

1. Create a token named "GitHub Actions" or "CI/CD"
2. Add to your CI/CD secrets
3. Consider limiting scope if supported

> **Best Practice:** Each developer and each CI/CD pipeline should have its own token. This allows you to revoke access individually without affecting others.

---

## Step 5: Set Up Shared Credentials

### App Store Connect Credential

Add credentials that the whole team can use:

1. Go to **App Store Connect** → **Add Credential**
2. Upload your API key
3. The credential is now available to all team members

### Google Play Credential

1. Go to **Google Play** → **Add Credential**
2. Upload the service account JSON
3. All members can now ship Android builds

### Keystores

1. Go to **Keystores** → **Upload Keystore**
2. Upload your signing keystore
3. Activate it as the default
4. Team members can sign builds without accessing the keystore directly

---

## Step 6: Member Onboarding

Guide new team members through setup:

### 1. Accept Invitation

New members click the invitation link and create an account (or log in if they already have one).

### 2. Generate Personal Token

```bash
# In MySigner dashboard
# Go to API Tokens → Create Token
```

### 3. Configure CLI

```bash
# Run onboarding wizard
mysigner onboard

# Or login directly (interactive - will prompt for API URL, email, and token)
mysigner login
```

### 4. Verify Setup

```bash
mysigner doctor
```

### 5. Start Shipping

```bash
cd my-app
mysigner ship testflight
```

---

## Managing Team Members

### Change a Member's Role

1. Go to **Organization Settings** → **Team**
2. Find the member
3. Click the role dropdown
4. Select new role

### Remove a Member

1. Go to **Organization Settings** → **Team**
2. Find the member
3. Click **Remove**
4. Confirm removal

> **Note:** Removing a member doesn't revoke their personal API tokens immediately. Consider reminding them to delete their tokens or revoking organization access.

### Transfer Ownership *(not yet available)*

There's no in-app Transfer Ownership flow today. The Owner of an organisation is set when the organisation is created and is fixed thereafter. If you need to reassign ownership (e.g. when a founding owner leaves the company), please contact support.

A future release will add a self-service Transfer Ownership flow. When it ships, the action will appear in the [Audit Log](/docs/dashboard/audit-log) on Team plans.

---

## Multiple Organizations

Team members can belong to multiple organizations:

### Switch Organizations (Dashboard)

1. Click organization name in the sidebar
2. Select a different organization

### Switch Organizations (CLI)

```bash
# List organizations
mysigner orgs

# Switch to a different organization (interactive selection)
mysigner switch
```

---

## Best Practices

### Credential Management

1. **One credential per team** - Don't create personal ASC credentials
2. **Use Admin access** - ASC API keys should have Admin role
3. **Rotate periodically** - Regenerate keys annually

### Token Management

1. **Personal tokens** - Each developer has their own
2. **CI/CD tokens** - Dedicated tokens for automation
3. **Descriptive names** - "John's MacBook" vs "CI/CD GitHub"
4. **Revoke unused** - Remove tokens when people leave

### Role Assignment

| Team Member | Suggested Role |
|-------------|----------------|
| Lead developer | Owner or Admin |
| Senior developers | Admin |
| Developers | Developer |
| Contractors | Developer or Viewer |
| Read-only access | Viewer |
| CI/CD systems | N/A (use tokens) |

### Security

1. **Enable 2FA** - Encourage all members to enable two-factor auth
2. **Review access** - Periodically audit team membership. On Team plans, the [Audit Log](/docs/dashboard/audit-log) records every invitation, role change, and removal so you can see *who* did *what* and *when*.
3. **Minimal permissions** - Give members the lowest role needed (prefer Viewer for read-only needs). Use the [Permissions matrix](/docs/dashboard/permissions) to confirm exactly which capabilities each role unlocks.
4. **Credential visibility** - Sensitive credential data is hidden from Developers and Viewers
5. **Centralised identity** *(Team plan)* — set up [SAML 2.0 SSO](/docs/dashboard/sso) with your IdP. With **enforcement** turned on, password / Google / GitHub / Apple login is disabled for everyone except the Owner (who keeps password access as a break-glass recovery).
6. **Audit credential changes** *(Team plan)* — credential add / activate / remove events are written to the audit log automatically, giving you a timestamped record of who changed what for internal review.

---

## Common Scenarios

### Freelancer Access

For temporary contractors:

1. Invite as **Developer** (if they need to ship) or **Viewer** (read-only)
2. Create time-limited notes
3. Remove when project ends
4. Remind them to delete their token

### Team Lead Setup

For team leads who manage releases:

1. Assign **Admin** role
2. They can manage team
3. They can add/update credentials
4. Cannot delete the organization

### Developer Access

For regular developers who ship builds:

1. Assign **Developer** role
2. They can ship builds and manage releases
3. They can invite other Developers or Viewers
4. Cannot manage credentials or keystores

### CI/CD Only Access

For automated systems:

1. No need to invite as member
2. Generate a dedicated API token
3. Name it clearly ("GitHub Actions - Production")
4. Store in CI/CD secrets

---

## Troubleshooting

### "Not authorized" error

Member doesn't have permission for the action.

**Fix:** Check their role and upgrade if needed.

### "Organization not found"

CLI is configured for a different organization.

**Fix:**
```bash
mysigner orgs    # List organizations
mysigner switch  # Change organization
```

### Invitation email not received

**Check:**
1. Spam/junk folder
2. Correct email address
3. Email provider isn't blocking

**Fix:** Resend invitation from Team page.

### Can't remove last Admin

At least one Admin must remain in the organisation. The Owner always counts as an Admin for this check.

**Fix:** Promote another member to Admin first, then remove the original. The Owner cannot be removed at all (ownership is permanent until support reassigns it).

---

## Next Steps

**Setup:**
- [Credentials Setup](/docs/dashboard/credentials) - Configure ASC and Google Play
- [iOS Resources](/docs/dashboard/ios-resources) - Manage certificates and profiles
- [API Tokens](/docs/dashboard/api-tokens) - Token management details

**Plan management:**
- [14-Day Pro Trial](/docs/dashboard/trial) - How the auto-trial works
- [Pricing & Plans](/docs/dashboard/pricing-plans) - Seat limits and tier comparison

**Team plan features (multi-seat collaboration):**
- [Permissions](/docs/dashboard/permissions) - Read-only RBAC matrix wired to Pundit
- [Audit Log](/docs/dashboard/audit-log) - 365-day immutable record of sensitive actions
- [SSO (SAML 2.0)](/docs/dashboard/sso) - In-app summary with link to full setup guide

---

## CLI Commands

| Command | Description |
|---------|-------------|
| `mysigner orgs` | List your organizations |
| `mysigner switch` | Change active organization |
| `mysigner status` | Show current organization and user |
