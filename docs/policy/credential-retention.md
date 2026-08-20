# Credential Retention Policy

**Audience:** Operators, admins, and security reviewers.
**Last updated:** 2026-05-26
**Status:** Authoritative. Code MUST conform; if a behavior diverges from this
document, fix the code or update the doc (Rule 12 — fail loud).

## Scope

This policy covers **signing credentials** stored on the MySigner server:

- App Store Connect API keys (`.p8` PEM under `AppStoreConnectCredential`)
- Apple Search Ads private keys (PEM under `AppleAdsCredential`)
- Google Play service-account JSON (`GooglePlayCredential`)
- Android keystores and their passwords (`AndroidKeystore`)

Local-only credentials (mysigner-22, stored in the user's macOS Keychain or an
encrypted file under `~/.mysigner/credentials/`) follow a parallel policy on
the CLI side and are wiped during `mysigner logout` when the user opts in to
the same purge.

## Retention principles

1. **Cancellation never deletes data; only user-initiated deletion does.**
   A free tier exists forever. Downgrades, expired trials, and cancelled
   paid subscriptions all leave stored credentials untouched.
2. **Logout IS user-initiated deletion** when the user opts in. The
   `mysigner logout` command (CLI) and the `DELETE
   /api/v1/organizations/:organization_id/credentials` endpoint (server)
   together implement the user-driven purge.
3. **Org deletion cascades.** Destroying an `Organization` row cascades
   `dependent: :destroy` to every credential association (see
   `app/models/organization.rb`). No credential survives an org delete.
4. **AuditEvents survive credential deletes.** The `belongs_to :resource`
   on `AuditEvent` is optional; a credential's audit history remains
   queryable after the credential row is gone. This is intentional — the
   audit log is the system of record for "what was here, and what
   happened to it."

## What gets purged on `mysigner logout --purge`

When the user invokes `mysigner logout` and confirms the prompt (default
**No**), or passes `--purge` (skip prompt, assume **Yes**), the CLI:

1. Calls `DELETE /api/v1/organizations/:organization_id/credentials` with
   the current organization's API token. The server hard-deletes every:
   - `AppStoreConnectCredential`
   - `AppleAdsCredential`
   - `GooglePlayCredential`
   - `AndroidKeystore`
   row owned by that organization, including the KMS-wrapped envelope
   columns (the envelope lives on the same row as the credential — when the
   row goes, the envelope goes).
2. Wipes the local CLI's Keychain / encrypted-file entries for the four
   `LocalCredentials` kinds (`:asc`, `:apple_ads`, `:google_play`,
   `:android_keystore`).
3. Clears `~/.mysigner/config.yml`.

Per row deleted, the server emits a `credential_destroyed_on_logout`
`AuditEvent` with metadata `{kind:, credential_id:, organization_id:}` —
recorded BEFORE the destroy call so `resource_id` is preserved.

The endpoint requires:

- Admin or owner role on the organization (`OrganizationPolicy#manage_credentials?`)
- A token with `write` scope
- The `X-User-Email` header (`require_user_email!`, mysigner-30)
- The token's `organization_id` must match the URL's `:organization_id`
  (`verify_token_organization_access!`)

Developer- and viewer-role members are rejected with `403 Forbidden`.

## What does NOT get purged on logout

- Other organizations the user belongs to keep their credentials. The
  endpoint is org-scoped because the API token is org-scoped. To purge
  credentials in another org, `mysigner switch` into it and run the same
  command.
- `AuditEvent` rows. They survive forever (subject to the
  `AuditEventRetentionJob` retention window applied uniformly across
  audit history — not specific to credential deletes).
- `ApiToken` rows. The CLI's existing logout already discards the local
  copy of the token; the server-side token row is unaffected unless the
  user revokes it explicitly via the web dashboard.

## How free-tier users keep credentials forever

A free-tier organization (`plan_tier: :free`) retains every stored
credential as long as the organization exists. There is no background job
that prunes inactive credentials, expired free trials, or cancelled
subscriptions. The only paths to deletion are:

1. The owner runs `mysigner logout --purge` (the path documented above).
2. The owner deletes the organization from the web dashboard
   (cascades via `dependent: :destroy` to credentials).
3. The owner soft-deletes their account (`users#destroy`); the 90-day
   restoration window applies; full credential deletion happens when the
   org is hard-deleted at the end of that window.

## Implementation references

- Server controller: `app/controllers/api/v1/credentials_controller.rb`
- Route: `config/routes.rb` (`delete "credentials"` under the
  `/api/v1/organizations/:organization_id` namespace)
- Pundit policy: `OrganizationPolicy#manage_credentials?` (admin or owner)
- Audit action constant: `AuditEvent::ACTIONS` includes
  `credential_destroyed_on_logout`
- CLI command: `Mysigner::CLI#logout` in `lib/mysigner/cli/auth_commands.rb`
- Tests: `spec/requests/api/v1/credentials_destroy_spec.rb` (server),
  `spec/cli/logout_spec.rb` (CLI)
