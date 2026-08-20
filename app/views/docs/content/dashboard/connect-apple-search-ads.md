---
title: Connect Apple Search Ads
description: OAuth setup for the Apple Search Ads API, required for keyword popularity
order: 9.1
---

# Connect Apple Search Ads

Connecting an Apple Search Ads (Apple Ads Advanced) account lets MySigner read Apple's own keyword popularity data for your app. This is what powers the 1-to-5 dot Popularity indicator in the [Keywords & ASO](/docs/dashboard/keywords) workspace. The connection is OAuth-based — MySigner never sees your Apple ID password.

> **Pro or Team plan required.** On Free the banner is hidden.

---

## What is Apple Ads Advanced?

Apple Search Ads has two products: **Basic** (simple cost-per-install) and **Advanced** (the full console, including the API). The API we need is part of Advanced. Signup is free, takes ~5 minutes, and **there is no minimum spend** — you can create the account, generate an API key, and never run a single ad.

<!-- TODO: screenshot of Apple Ads Advanced signup page -->

---

## Step 1 — Create an Apple Ads Advanced account

Skip if you already have one.

1. Go to [ads.apple.com](https://ads.apple.com) and sign in with your Apple developer Apple ID.
2. Choose **Advanced** when asked.
3. Confirm business details. No payment method required.
4. Wait for activation — usually instant.

---

## Step 2 — Generate a P256 API key

Apple's API authenticates with an ECDSA P-256 key.

```bash
openssl ecparam -name prime256v1 -genkey -noout -out key.p8
openssl ec -in key.p8 -pubout -out public.pem
```

You now have `key.p8` (private — keep safe) and `public.pem` (you'll upload this to Apple). If you'd rather not use the terminal, Apple's UI can generate the keypair under **Account Settings → API → Generate API Certificate**.

<!-- TODO: screenshot of Apple Ads API settings page -->

---

## Step 3 — Register the public key with Apple

1. In the Apple Ads console: **Account Settings** → **API** → **Add Certificate**.
2. Upload `public.pem`.
3. Pick the ACL role — **API Account Manager** is the minimum for read-only popularity.
4. Save. Apple shows you three values: **Client ID**, **Team ID**, and **Key ID**. Copy all three.

<!-- TODO: screenshot of the three IDs on the Apple Ads certificate page -->

---

## Step 4 — Paste into MySigner

1. In MySigner, open **Keywords & ASO** and click **Connect Apple Search Ads**.
2. Fill in the form:
   - **Client ID**, **Team ID**, **Key ID** — from the Apple Ads API page
   - **Private Key (PEM)** — paste the full contents of `key.p8`, including the `-----BEGIN EC PRIVATE KEY-----` and `-----END EC PRIVATE KEY-----` lines
3. Click **Connect**.

MySigner runs an OAuth test handshake against Apple's token endpoint. On success you'll see a green **Connected** badge and the Popularity column starts populating within a few minutes. The private key is encrypted at rest and never shown back in the UI.

---

## If it fails

| Error | Cause | Fix |
|-------|-------|-----|
| `INVALID_CLIENT` | Client ID typo, or certificate hasn't finished registering | Check the ID; wait 60s and retry |
| `invalid_grant` | Team ID doesn't match the Client ID's org | Confirm both came from the same Apple Ads account |
| `Key ID not found` | Key ID mismatch, or public key doesn't pair with the pasted private key | Regenerate the keypair and re-register |
| `BEGIN/END markers missing` | You pasted only the middle of the `.p8` file | Include both the header and footer lines verbatim |
| `Revoked certificate` | The key was deleted in Apple Ads | Generate a new key, re-register, update MySigner |

If the handshake keeps failing, try a fresh keypair — occasionally Apple's certificate takes a few minutes to propagate.

---

## What happens next

- **Popularity refresh** runs daily, pulling Apple's 5-to-100 score for every keyword Apple recommends for your app (see [Keyword popularity](/docs/dashboard/keyword-popularity)).
- Rank tracking keeps working on the same cadence — popularity is additive.
- Disconnect any time from the **Keywords & ASO** page (use **Edit credentials** → **Disconnect**); the encrypted key is deleted.

---

## Related

- [Keywords & ASO](/docs/dashboard/keywords) - The ASO workspace overview
- [Keyword popularity](/docs/dashboard/keyword-popularity) - How the 1-to-5 dots map to the raw score
- [Keyword rank explained](/docs/dashboard/keyword-rank-explained) - How rank tracking works
- [Credentials](/docs/dashboard/credentials) - App Store Connect credentials (distinct from Search Ads)
