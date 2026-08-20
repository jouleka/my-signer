---
title: App Store Connect API Key Setup Guide (2026)
description: Step-by-step guide to creating, downloading, and using an App Store Connect API key for CI uploads and automated TestFlight submissions.
order: 4
---

# App Store Connect API Key Setup Guide (2026)

The shortest summary: in App Store Connect, go to Users and Access → Integrations → App Store Connect API and create a new key. Download the `.p8` file (only available once), save the Issuer ID and Key ID, then use them with `xcrun altool` or any tool that uploads to TestFlight.

Apple deprecated app-specific-password authentication for the notary service in late 2023, and App Store Connect API keys are the recommended path for App Store uploads going forward. If you're setting up CI for an iOS app today, you need an API key. This guide walks through it cleanly without the missing-screenshot frustration most other guides have.

---

## What an ASC API Key Is

An ASC API key is a JWT-signing credential that gives a tool the ability to call App Store Connect APIs on your behalf. Each key consists of three pieces:

- **Issuer ID**: UUID tied to your App Store Connect organization. Reused across every key you create.
- **Key ID**: 10-character string unique to this key (e.g., `ABCD1234EF`).
- **Private key file**: the `.p8` itself, containing the ECDSA P-256 private key.

The `.p8` is shown to you exactly once at creation. If you lose it, you have to revoke the key and create a new one.

---

## Permissions: What Role to Pick

App Store Connect has the standard team roles, and keys can be assigned any of them. The roles most relevant to API-key automation:

| Role                | Common use case                                                  |
| ------------------- | ---------------------------------------------------------------- |
| **Admin**           | Full access (Account Holder and Admin can mint keys).            |
| **Finance**         | Financial reports.                                               |
| **App Manager**     | Manage apps, metadata, builds, submit for review.                |
| **Developer**       | Manage builds and metadata; upload to TestFlight.                |
| **Marketing**       | Listings and screenshots; no build access.                       |
| **Sales**           | Sales reports.                                                   |
| **Customer Support**| Respond to customer messages / reviews.                          |
| **Access to Reports**| Read-only reporting.                                            |

For TestFlight uploads in CI, Developer is enough; if you want to submit for App Store review end-to-end, you need App Manager. Only Account Holder or Admin users can create the keys themselves, but the keys can be assigned any of the roles above.

Pick the least-privileged role that works. If your CI gets compromised, the blast radius is whatever this key can do.

---

## Step-by-Step: Creating the Key

1. Open [App Store Connect](https://appstoreconnect.apple.com) and sign in with your **Account Holder** or **Admin** Apple ID. Lower roles can't manage keys.

2. Click **Users and Access** in the top nav.

3. In the left sidebar, under **Integrations**, click **App Store Connect API**.

4. The first time you do this, Apple may show a **Request Access** screen. Click it and wait; this is usually instant for existing developer accounts but can take a few minutes.

5. You'll see a list of keys. Click the **+** icon next to "Active" to create a new one.

6. **Name the key.** Use something specific: `CI - GitHub Actions - YourApp` or `MySigner - TestFlight Upload`. You can't change it later, but you can revoke and recreate.

7. **Pick the access role.** Per above, Developer for most CI uploads, App Manager if you also submit for review.

8. Click **Generate**.

9. The key appears in the list. Click **Download API Key** on the right. You'll get a file named `AuthKey_<KEY_ID>.p8`.

10. **Save the file somewhere safe.** You cannot download it again. If you lose it, you must revoke and recreate the key.

11. Also save the **Issuer ID**, shown at the top of the Keys page. It looks like `12345678-1234-1234-1234-123456789012`.

12. The **Key ID** is in the filename and in the row of your new key.

You now have all three pieces.

---

## Where to Save the `.p8` File

For local development:

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_ABCD1234EF.p8 ~/.appstoreconnect/private_keys/
```

`xcrun altool` automatically looks for `.p8` files in that directory. As long as the filename matches `AuthKey_<KEY_ID>.p8`, it picks the key up without you specifying the path.

For CI, **never commit the `.p8` to your repo.** Two safer options:

1. **Base64-encode it and store as a CI secret.** Then decode at runtime:
   ```bash
   echo "$ASC_API_KEY_BASE64" | base64 --decode > /tmp/AuthKey_ABCD1234EF.p8
   ```
2. **Use a secrets manager** (1Password CLI, AWS Secrets Manager, etc.) and pull it at job start.

---

## Using the Key with `xcrun altool`

The current recommended invocation uses `--upload-package` and hyphenated flags:

```bash
xcrun altool --upload-package build/YourApp.ipa \
  --type ios \
  --apple-id <YOUR_APP_APPLE_ID> \
  --bundle-id com.your.bundle \
  --bundle-version 1 \
  --bundle-short-version-string 1.0 \
  --api-key ABCD1234EF \
  --api-issuer 12345678-1234-1234-1234-123456789012
```

altool doesn't accept a custom `--p8-path` flag. It searches a fixed list of directories (`./private_keys`, `~/private_keys`, `~/.private_keys`, `~/.appstoreconnect/private_keys`) plus the directory in `$API_PRIVATE_KEYS_DIR`. Easiest path: keep the file in `~/.appstoreconnect/private_keys/`.

---

## Using the Key with the ASC REST API Directly

If you're calling App Store Connect API endpoints directly, you generate a short-lived JWT signed with the `.p8`. Most languages have a JWT library.

Python example (needs `pip install pyjwt cryptography`):

```python
import jwt
import time

KEY_ID = "ABCD1234EF"
ISSUER_ID = "12345678-1234-1234-1234-123456789012"

with open("AuthKey_ABCD1234EF.p8", "r") as f:
    private_key = f.read()

now = int(time.time())
token = jwt.encode(
    {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 20 * 60,  # 20 minutes max
        "aud": "appstoreconnect-v1"
    },
    private_key,
    algorithm="ES256",
    headers={"kid": KEY_ID, "typ": "JWT"}
)

# Use the token as a Bearer auth header
```

JWTs for ASC must be **ES256** signed and expire in **20 minutes or less** (`exp` ≤ `iat` + 1200).

---

## Using the Key with MySigner

If you don't want to hand-roll the JWT signing or the altool flow, MySigner handles the whole ASC integration for you. Upload your `.p8` to the dashboard once:

1. Sign in at [mysigner.dev](https://mysigner.dev)
2. Settings → **App Store Connect**
3. Click **Add credential**, paste the Issuer ID and Key ID, upload the `.p8` file
4. The CLI now uses this credential automatically for any `mysigner ship` command

```bash
mysigner ship testflight
```

The CLI reads the credential from the dashboard, signs a JWT per upload, and handles validation + polling + submission for you.

The `.p8` is uploaded to MySigner and encrypted at rest with AWS-KMS envelope encryption — a unique per-credential AES-256-GCM data key, bound to the record by an encryption context. It is decrypted server-side only at the moment a JWT is signed for an upload, and is never stored in plaintext.

---

## Rotating and Revoking Keys

We recommend rotating ASC API keys every 6-12 months, especially the ones used in CI. Apple doesn't mandate a rotation cadence, but treating any long-lived credential as something to rotate yearly is sensible. To rotate:

1. Create a new key in ASC.
2. Update CI / MySigner / wherever the old key is used with the new credential.
3. Test a build to verify the new key works.
4. Revoke the old key in ASC (Users and Access → Keys → click the key → Revoke).

If you suspect a key was leaked, revoke it immediately. Apple invalidates JWTs signed by a revoked key; treat revocation as effective right away.

---

## Common Errors

### `Could not load private key`
The `.p8` file isn't where the tool expects. For altool, that's `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` (or `./private_keys/...`, or the current directory).

### `Unauthorized: 401`
Three common causes: (a) the JWT expired (must be < 20 min lifetime), (b) the Key ID or Issuer ID is wrong, (c) the role assigned to the key doesn't allow the action you're trying.

### `Forbidden: 403`
The key's role is too restrictive. Upload to TestFlight needs at least Developer. Submitting for review needs App Manager.

### `The app does not have a primary language set`
Not a key issue. Your app's metadata in ASC is missing a primary language; fix it under ASC → your app → App Information.

---

## TL;DR

Generate the key once. Save the `.p8` somewhere safe and never commit it. Pair it with Issuer ID and Key ID. Use the Developer role for TestFlight uploads or App Manager for full submission flows. Rotate roughly once a year.

If you'd rather skip all of this, MySigner handles ASC API key management plus the build, sign, upload, poll, submit pipeline in one command. The free tier supports unlimited TestFlight shipping.

[Start free → mysigner.dev](https://mysigner.dev/users/sign_up)
