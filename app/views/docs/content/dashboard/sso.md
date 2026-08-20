---
title: SSO (SAML 2.0)
description: Set up Single Sign-On with Okta, Microsoft Entra, Google Workspace, or any SAML 2.0 IdP (Team plan)
order: 17
---

# SSO (SAML 2.0)

Sign in to MySigner with your existing identity provider — Okta, Microsoft Entra ID, Google Workspace, or any generic SAML 2.0 IdP. With **enforcement** turned on, password / Google / GitHub / Apple login is disabled for everyone in your organisation except the Owner (who keeps password access as a break-glass recovery).

> **Team plan only.** Free and Pro see a paywall page with the upgrade option.
>
> **For full setup with screenshots and IdP-specific instructions**, see the comprehensive [SSO_SETUP_GUIDE.md](https://github.com/jurgenleka/my-signer/blob/main/docs/SSO_SETUP_GUIDE.md) and [SSO_TESTING_GUIDE.md](https://github.com/jurgenleka/my-signer/blob/main/docs/SSO_TESTING_GUIDE.md). This page is the in-app reference.

---

## Supported identity providers

The configuration form has quick-start presets for:

- **Okta**
- **Microsoft Entra ID** (formerly Azure AD)
- **Google Workspace**
- **Generic SAML 2.0** — anything else (OneLogin, Auth0, Keycloak, Ping, ADFS, etc.)

Picking a preset pre-fills sensible defaults for that IdP — you still paste in your own URLs and certificate.

---

## What you configure

The form has these sections:

### IdP details (from your identity provider)

- **IdP Entity ID** — your IdP's identifier
- **IdP SSO URL** *(required)* — where MySigner redirects users to start the SAML flow
- **IdP SLO URL** *(optional)* — Single Logout endpoint (column accepted, dispatch coming soon)
- **IdP x509 Certificate** — paste the PEM-encoded certificate (must include `-----BEGIN CERTIFICATE-----` / `-----END CERTIFICATE-----` markers). Validated with OpenSSL on save and **encrypted at rest**.
- **Name ID format** — Email (default), Persistent, or Unspecified

### Provisioning rules

- **Default role for new SSO users** — Admin / Developer / Viewer (default Developer). Used when an SSO assertion arrives for a user MySigner has never seen before.
- **Verified email domains** — one per line. New SSO users with email domains in this list are auto-provisioned. Existing users are *only auto-linked* if the asserted email's domain is on this list — protecting against cross-org account takeover. Empty list = no auto-linking (fail-safe).

### Mode

- **Enable SSO** — turns the `/auth/sso?slug={your-org-slug}` endpoint on
- **Enforce SSO** — blocks password / Google / GitHub / Apple login for *every member* except the Owner. Without this, SSO is *available* but optional.

---

## Service-Provider URLs (give these to your IdP)

Once SSO is enabled for your organisation, the **Show** page displays three URLs you'll need on the IdP side:

- **SP Entity ID** (also doubles as the metadata URL)
- **ACS URL** — `{base_url}/users/auth/saml/callback`
- **Test URL** — `/auth/sso?slug={your-org-slug}` for sanity-checking the round trip

Each URL has a copy button. The SP entity ID is computed from your organisation slug at request time (not stored), so renaming the slug transparently updates the metadata your IdP fetches.

---

## Enforcement and the break-glass account

When you enable **Enforce SSO**, MySigner blocks every other login method for organisation members:

- Email + password ❌
- Google OAuth ❌
- GitHub OAuth ❌
- Apple Sign-In ❌

**Except for the Owner.** The Owner always retains password login as a break-glass recovery — the form warns about this when you tick the enforcement checkbox. Without that exception, a misconfigured IdP could lock everyone out.

If enforcement is **on** but SSO is **disabled** (an inconsistent state — usually mid-setup), the Show page displays a yellow warning banner so you can fix it before users get blocked.

---

## Testing your setup

Use the **Test SSO login** button on the Show page (visible when SSO is enabled). It opens the test URL in a new tab so you can confirm the full IdP → MySigner round trip works without disrupting other users.

If something goes wrong, the failure is logged in your [Audit Log](/docs/dashboard/audit-log) as `sso_login_failed` with the error class — useful for debugging IdP misconfigurations.

---

## Just-in-time provisioning

When a user signs in via SSO for the first time:

- If their email matches a **verified domain**, they're either auto-linked to an existing MySigner account or auto-created with the **default role** you set
- If the email's domain is **not** on the verified list, the SSO sign-in is refused (cross-org safety)
- The new (or linked) user is added to your organisation immediately — no admin approval step

---

## Removing SSO

To disable temporarily, edit the configuration and uncheck **Enable SSO**.

To remove entirely, click **Remove** on the Show page. The action is recorded in the audit log as `sso_configuration_removed`. Existing users keep their accounts and can log in with password or OAuth (assuming enforcement was off, or the Owner re-enables those flows first).

---

## Audit trail

These events appear in the [Audit Log](/docs/dashboard/audit-log):

- `sso_configuration_created`, `sso_configuration_updated`, `sso_configuration_removed`
- `sso_login`, `sso_login_failed`

---

## Related

- [SSO_SETUP_GUIDE.md](https://github.com/jurgenleka/my-signer/blob/main/docs/SSO_SETUP_GUIDE.md) - Full setup with Okta / Entra / Google Workspace screenshots
- [SSO_TESTING_GUIDE.md](https://github.com/jurgenleka/my-signer/blob/main/docs/SSO_TESTING_GUIDE.md) - End-to-end testing playbook
- [Permissions](/docs/dashboard/permissions) - Role assignments for SSO-provisioned users
- [Audit Log](/docs/dashboard/audit-log) - SSO sign-ins and config changes
- [Pricing & Plans](/docs/dashboard/pricing-plans) - Team plan features
