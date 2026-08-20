---
title: Organizations
description: Create and manage organizations with team members and roles
order: 1
---

# Organizations

Organizations are the top-level container in MySigner for managing apps, credentials, and team collaboration.

---

## Overview

Every resource in MySigner belongs to an organization:

- **Credentials** - App Store Connect and Google Play API keys
- **Apps** - iOS and Android apps synced from the stores
- **Certificates & Profiles** - iOS code signing resources
- **Keystores** - Android signing keys
- **Team Members** - Users with role-based access

---

## Creating an Organization

1. Go to **Organizations** in the sidebar
2. Click **New Organization**
3. Enter a name (e.g., "Acme Inc" or "Mobile Team")
4. Click **Create**

You become the **Owner** of the organization automatically.

> **Plan note:** Organization count is plan-limited. If you hit the cap, MySigner will show an upgrade prompt and point you to the pricing page. Billing is still handled manually during early access.

---

## Organization Settings

From the organization page, you can:

### General Settings

- **Edit Name** - Click the edit button to rename
- **Delete Organization** - Permanently remove (Owner only)

### Team Management

- **Invite Members** - Send email invitations
- **Manage Roles** - Change member permissions
- **Remove Members** - Revoke access

### Sync Controls

- **Sync iOS** - Refresh data from App Store Connect
- **Sync Android** - Refresh data from Google Play

---

## Team Members and Roles

MySigner has three assignable **roles** (Admin, Developer, Viewer) plus a special **Owner** status that belongs to one user per organization.

> **Owner is not a selectable role.** When you create an organization you become its Owner automatically. Ownership is a separate organization-level status — every Owner also has a membership row, and the Owner-status grants the same permissions as Admin plus the ability to delete the organization. **Ownership is currently permanent for the lifetime of the organisation** — there is no in-app Transfer Ownership flow yet (see below). When you invite someone to the team, the role dropdown only shows Admin, Developer, and Viewer.

### Owner *(organization-level status, one per org)*

- Full access to everything Admin has, plus:
- Can delete the organization
- Cannot currently be changed in-app — ownership is fixed for the lifetime of the organisation (a Transfer Ownership UI is on the roadmap; until then, contact support if you need to reassign)
- Cannot be removed from the team like a regular member

### Admin *(role)*

- Manage team members (invite any role, remove, change roles)
- Manage credentials (add, edit, delete)
- Manage all resources (keystores, devices, profiles)
- Cannot delete organization

### Developer *(role)*

- Ship builds and trigger syncs
- Manage app resources (releases, app config)
- Create API tokens (Read/Write scope only — Admin scope requires Admin or Owner)
- Invite new members (Developer or Viewer roles only)
- View credentials (sensitive values hidden)
- Cannot manage credentials, keystores, or devices

### Viewer *(role)*

- View all resources (read-only)
- View credentials (sensitive values hidden)
- Cannot ship builds, create tokens, or make changes

### Role Permissions

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

> **Transfer ownership is not yet available in-app** — the Owner is fixed for the lifetime of the organisation. A Transfer Ownership UI is on the roadmap; until then, contact support if you need to reassign ownership.

---

## Inviting Team Members

### Send an Invitation

1. Go to your organization page
2. Scroll to **Team** section
3. Click **Invite Member**
4. Enter the email address
5. Select a role (Admin, Developer, or Viewer)
6. Click **Send Invitation**

> **Note:** Developers can only invite other Developers or Viewers. Only Admins and Owners can invite Admins.

> **Plan note:** Team seats are also plan-limited per organization. If the invite flow is blocked, use the upgrade prompt or visit the pricing page to request a higher tier.

### Invitation Status

| Status | Description |
|--------|-------------|
| Pending | Invitation sent, awaiting response |
| Accepted | Member joined the organization |
| Expired | Not accepted within 7 days |

### Resend Invitation

If an invitation expires or wasn't received:

1. Find the pending invitation
2. Click **Resend**
3. A new invitation email is sent

---

## Managing Members

### Change a Role

1. Go to **Team** section
2. Find the member
3. Click the role dropdown
4. Select the new role

### Remove a Member

1. Go to **Team** section
2. Find the member
3. Click **Remove**
4. Confirm the removal

> **Note:** Removing a member doesn't automatically revoke their API tokens. Remind them to delete tokens or revoke from the API Tokens page.

### Transfer Ownership *(not yet available)*

There is no in-app Transfer Ownership flow today. The Owner of an organisation is set when the organisation is created and is fixed thereafter. If you need to reassign ownership (e.g. when a founding owner leaves the company), please contact support.

A future release will add a self-service Transfer Ownership flow. When it ships, the action will be recorded in the [Audit Log](/docs/dashboard/audit-log) on Team plans.

---

## Switching Organizations

### In the Dashboard

1. Click the organization name in the sidebar
2. Select a different organization from the list

### With the CLI

```bash
# List your organizations
mysigner orgs

# Switch interactively
mysigner switch
```

---

## Multiple Teams

You can create separate organizations for different purposes:

| Organization | Use Case |
|--------------|----------|
| Acme Inc - Production | Production apps and credentials |
| Acme Inc - Dev | Development and testing |
| Personal Projects | Side projects |
| Client: BigCorp | Client work with separate billing |

Each organization has its own:
- Credentials
- Team members
- Resources
- Billing (if applicable)

---

## Best Practices

### Organization Structure

- **One organization per company/team** - Keep related apps together
- **Separate production and dev** - Use different organizations if you need isolated credentials
- **Descriptive names** - Make it clear what the organization is for

### Team Management

- **Minimal permissions** - Give members the lowest role they need (see the [Permissions matrix](/docs/dashboard/permissions) for the full role-vs-capability table)
- **Admin for leads** - Team leads and those managing credentials get Admin
- **Developer for engineers** - Developers who ship builds get Developer role
- **Viewer for stakeholders** - Read-only access for those who don't need to make changes
- **Regular audits** - Review team membership periodically. On Team plans, every membership change (invitation sent, accepted, cancelled, member added, role changed, member removed) is recorded in the [Audit Log](/docs/dashboard/audit-log) so you can review the full history.

### Security

- **Rotate credentials** - Update API keys annually
- **Enable 2FA** - Encourage all members to enable two-factor auth
- **Use SSO on Team plans** - Centralise identity with [SAML 2.0 SSO](/docs/dashboard/sso) (Okta, Microsoft Entra, Google Workspace, or any generic IdP). Optional enforcement blocks password / OAuth login for everyone except the Owner.
- **Revoke on departure** - Remove members when they leave the team
- **Separate CI tokens** - Use dedicated tokens for automation

---

## Related

- [Credentials](/docs/dashboard/credentials) - Set up App Store Connect and Google Play
- [API Tokens](/docs/dashboard/api-tokens) - Generate tokens for CLI access
- [Permissions](/docs/dashboard/permissions) - Role-based access control matrix *(Team)*
- [Audit Log](/docs/dashboard/audit-log) - Track sensitive actions across your organisation *(Team)*
- [SSO (SAML 2.0)](/docs/dashboard/sso) - Single Sign-On with your IdP *(Team)*
- [Pricing & Plans](/docs/dashboard/pricing-plans) - Seat limits and tier comparison
- [Team Setup Guide](/docs/guides/team-setup) - Detailed walkthrough
