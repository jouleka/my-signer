---
title: API Tokens
description: Generate and manage API tokens for CLI and CI/CD
order: 6
---

# API Tokens

API tokens authenticate the MySigner CLI and enable automation through CI/CD pipelines.

---

## Overview

API tokens are used for:

- **CLI authentication** - Run `mysigner` commands from your terminal
- **CI/CD pipelines** - Automated builds and deployments
- **API access** - Programmatic access to MySigner features

---

## Token Scopes

Tokens have different permission levels:

| Scope | Permissions |
|-------|-------------|
| **Read** | View resources, download profiles/certificates |
| **Write** | Read + upload builds, manage releases |
| **Admin** | Write + manage credentials, keystores, team (if user has permission) |

> **Note:** A token can only have scopes up to the user's organization role. Only Admins and Owners can create Admin scope tokens. See the [Permissions matrix](/docs/dashboard/permissions) for the full role-vs-scope authorisation rules.

### Scope Examples

| User Role | Can Create |
|-----------|------------|
| Owner | Read, Write, Admin |
| Admin | Read, Write, Admin |
| Developer | Read, Write only |
| Viewer | Cannot create tokens |

---

## Creating a Token

### Personal Token (CLI)

1. Go to **Organizations** → select your organization
2. Click **API Tokens** in the sidebar
3. Click **New Token**
4. Enter a descriptive name (e.g., "MacBook Pro - John")
5. Select scope level (Read, Write, or Admin)
6. Choose expiration:
   - 30 days
   - 90 days (default)
   - 1 year
   - Never expires
7. Click **Create**
8. **Copy the token immediately** - you won't see it again!

### CI/CD Token

For automated pipelines, create a dedicated token:

1. Name it clearly: "GitHub Actions - Production"
2. Use Write scope (or Admin if managing credentials)
3. Set appropriate expiration
4. Store in CI/CD secrets

---

## Using Tokens

### CLI Authentication

Configure the CLI with your token:

```bash
# Interactive onboarding
mysigner onboard

# Or direct login (interactive - will prompt for API URL, email, and token)
mysigner login
```

The token is stored encrypted at rest in `~/.mysigner/config.yml` using AES-256-GCM. On macOS, the encryption key lives in the system Keychain. On Linux and Windows it lives in a `0600` file at `~/.mysigner/.encryption_key`. Either way, the token is never on disk in plaintext. For CI/CD, prefer the `MYSIGNER_API_TOKEN` environment variable so nothing is written to disk at all.

### CI/CD Configuration

In CI/CD pipelines, create the config file from your secrets:

#### GitHub Actions

```yaml
- name: Configure MySigner
  run: |
    mkdir -p ~/.mysigner
    cat > ~/.mysigner/config.yml << EOF
    api_url: "https://mysigner.dev"
    user_email: "${{ secrets.MYSIGNER_EMAIL }}"
    current_organization_id: ${{ secrets.MYSIGNER_ORG_ID }}
    organizations:
      "${{ secrets.MYSIGNER_ORG_ID }}":
        name: "CI"
        token: "${{ secrets.MYSIGNER_API_TOKEN }}"
    EOF
    chmod 600 ~/.mysigner/config.yml
```

#### GitLab CI

```yaml
before_script:
  - mkdir -p ~/.mysigner
  - |
    cat > ~/.mysigner/config.yml << EOF
    api_url: "https://mysigner.dev"
    user_email: "$MYSIGNER_EMAIL"
    current_organization_id: $MYSIGNER_ORG_ID
    organizations:
      "$MYSIGNER_ORG_ID":
        name: "CI"
        token: "$MYSIGNER_API_TOKEN"
    EOF
  - chmod 600 ~/.mysigner/config.yml
```

#### Bitrise

Add these as Secrets, then create the config file in a Script step:
- `MYSIGNER_EMAIL`
- `MYSIGNER_ORG_ID`
- `MYSIGNER_API_TOKEN`

> **Note:** The `MYSIGNER_API_URL` environment variable is supported for overriding the API URL default during `mysigner login`, but token authentication always uses the config file at `~/.mysigner/config.yml`.

### Additional environment variables

The CLI recognises a handful of extra environment variables that are useful in CI/CD:

| Variable | Purpose |
|----------|---------|
| `MYSIGNER_KEYSTORE_PASSWORD` | Android keystore password for non-interactive signing. |
| `MYSIGNER_KEY_PASSWORD` | Android signing-key password (falls back to `MYSIGNER_KEYSTORE_PASSWORD`). |
| `MYSIGNER_KEYSTORE_CACHE_HOURS` | TTL for the local keystore cache in hours (default `24`). |
| `MYSIGNER_VERBOSE` | Set to `1` to emit extra diagnostic logging. |
| `DEBUG` | Set to any truthy value to print backtraces and low-level error details. |

### API Requests

Use tokens directly in API requests:

```bash
curl -X GET https://mysigner.dev/api/v1/status \
  -H "Authorization: Bearer $MYSIGNER_TOKEN"
```

---

## Managing Tokens

### Viewing Tokens

1. Go to **API Tokens** for your organization
2. See all tokens with:
   - Name
   - Creator
   - Scopes
   - Created date
   - Expiration
   - Last used (if available)

### Revoking a Token

To revoke a token (immediate effect):

1. Find the token in the list
2. Click **Revoke**
3. Confirm the revocation

The token is immediately invalidated. Any CLI sessions or CI/CD pipelines using it will fail.

### Token Expiration

Tokens expire based on the setting chosen at creation:

| Expiration | Use Case |
|------------|----------|
| 30 days | Short-term access, contractors |
| 90 days | Regular development (default) |
| 1 year | Long-running CI/CD pipelines |
| Never | Permanent automation (use carefully) |

When a token expires:
- CLI commands fail with authentication error
- API requests return 401 Unauthorized
- Create a new token and update configurations

---

## Best Practices

### Naming Conventions

Use descriptive names that identify:
- **Device/machine**: "MacBook Pro - John"
- **Purpose**: "GitHub Actions - Production"
- **Environment**: "Staging CI/CD"

### Security

1. **Never share tokens** - Each user should have their own
2. **Never commit tokens** - Use secrets management
3. **Rotate regularly** - Replace tokens periodically
4. **Use minimal scope** - Only grant needed permissions
5. **Set expiration** - Avoid "never expires" when possible

### Token Hygiene

- **Review periodically** - Audit tokens quarterly
- **Revoke unused** - Remove tokens for departed team members
- **Separate by purpose** - Different tokens for different pipelines
- **Document** - Keep track of what each token is for

### CI/CD Recommendations

| Environment | Token Setup |
|-------------|-------------|
| Production | Dedicated Admin token, limited access |
| Staging | Write scope token |
| Development | Personal developer tokens |
| Per-pipeline | Separate tokens for each workflow |

---

## Token Recovery

### Lost Token

If you lose a token, you cannot retrieve it. You must:

1. Revoke the old token (if you know which one)
2. Create a new token
3. Update configurations with the new token

### Compromised Token

If a token may be compromised:

1. **Revoke immediately** - Go to API Tokens and revoke
2. **Audit activity** - Check recent builds and changes
3. **Create new token** - Generate a replacement
4. **Update secrets** - Update CI/CD and other systems

---

## Troubleshooting

### "Invalid token" error

The token is wrong, expired, or revoked.

**Fix:**
1. Verify the token is correct
2. Check if it's expired
3. Create a new token if needed

### "Insufficient scope" error

The token doesn't have permission for the action.

**Fix:**
1. Check what scope the action requires
2. Create a new token with appropriate scope
3. Or ask an Admin to perform the action

### "Token not found" error

The token doesn't exist (may have been revoked).

**Fix:**
1. Log in to the dashboard
2. Create a new token
3. Update your CLI: `mysigner login`

### Token not working in CI/CD

**Check:**
1. Environment variable is set correctly
2. Token hasn't expired
3. Token has correct scope
4. API URL is correct

---

## Audit trail *(Team plan)*

On Team plans, every API token created and revoked is recorded in the [Audit Log](/docs/dashboard/audit-log) as `api_token_created` / `api_token_revoked`. Use it during quarterly access reviews or after a contractor's engagement ends.

---

## Related

- [Getting Started](/docs/quickstart/getting-started) - Initial CLI setup
- [Auth Commands](/docs/commands/auth) - CLI authentication commands
- [CI/CD GitHub](/docs/guides/ci-cd-github) - GitHub Actions integration
- [Team Setup](/docs/guides/team-setup) - Team token management
- [Permissions](/docs/dashboard/permissions) - Role-based access for token scopes *(Team)*
- [Audit Log](/docs/dashboard/audit-log) - Track token creation and revocation *(Team)*
