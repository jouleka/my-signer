# BYOK Customer Setup Guide

**Audience:** Customer admins registering their own AWS KMS CMK.
**Last updated:** 2026-05-21
**Status:** Available to admin/owner on every plan tier. Revoking your CMK cuts both encrypt and decrypt access on our side.

> Throughout this guide, `${MYSIGNER_AWS_ACCOUNT_ID}` is a placeholder for
> MySigner's 12-digit AWS account ID. The dashboard surfaces the real value
> on the BYOK panel at setup time; you'll paste it directly from there.

## Who this is for

You're an admin or owner who wants to wrap your signing-credential DEKs
under a CMK that lives in **your** AWS account, not ours. With BYOK
configured, the key that gates decryption of your credentials sits behind
your own key policy. If you ever need to cut MySigner's access in a hurry,
you do it from your AWS console — no ticket, no waiting on us. This guide
walks you through creating the CMK, granting MySigner the minimum access we
need, and registering the ARN in MySigner.

## Prerequisites

- You're an **Admin or Owner** of your MySigner organization. Members
  without those roles can't manage BYOK regardless of plan tier — BYOK
  changes the cryptographic root for every credential in the org, so the
  role gate is intentionally tighter than ordinary credential management.
- You have an **AWS account** with permission to create and manage KMS CMKs
  (`kms:CreateKey`, `kms:PutKeyPolicy`, `kms:DescribeKey` on your side).
- You have your **AWS account's 12-digit ID** handy. You'll paste it as
  part of step 3.
- You'll need your **MySigner Organization ID** — the BYOK panel
  (Settings → Security → Bring Your Own Key) shows it on screen alongside
  `${MYSIGNER_AWS_ACCOUNT_ID}` so you can copy both into your key policy.

## What this changes for you

When BYOK is configured for your organization:

- Every new credential write is wrapped under **your** CMK. The DEK that
  encrypts your credential data is itself encrypted by your key, in your
  AWS account, governed by your key policy.
- Revoking MySigner's access to your CMK (by removing the policy statement,
  disabling the key, or scheduling deletion) immediately cuts our ability
  to read or write your credential data. The next decrypt attempt fails
  fast with the locked-copy message: "Your CMK is unreachable. Re-grant
  MySigner access or clear BYOK in Settings → Security." Subject to the
  in-flight DEK cache window described under Revocation below.
- You can **update your CMK ARN later** — paste a new ARN and we re-wrap
  all your existing credential envelopes with the new key in a single save.
- You can **clear BYOK at any time** — we re-wrap your envelopes back to
  MySigner's default CMK before nulling the column. Symmetric to register.

### What revoking your CMK actually cuts off

**Both the encrypt and the decrypt path.** Once BYOK is registered, every
credential write goes through your CMK, and every read unwraps the DEK
through your CMK too. If you revoke MySigner's access (by removing the
key-policy statement, disabling the key, or scheduling deletion), the next
decrypt attempt on your data fails fast with the locked-copy message
quoted above and any further writes are blocked the same way.

The one window to be aware of is the in-flight **DEK cache** (1-hour TTL)
on MySigner's side, described in detail under Revocation below. Already-
cached DEKs continue to decrypt for up to an hour after revocation; new
cache misses fail immediately. If you need instant lockout (e.g. you're
revoking in response to a compromise), contact support — we can purge the
cache on request.

## Step 1 — Create a CMK in your AWS account

Requirements (hard constraints today):

| Setting | Required value |
|---|---|
| Region | `us-east-1` |
| Key type | Symmetric |
| Key usage | Encrypt and decrypt |
| Key spec | `SYMMETRIC_DEFAULT` |
| Key material origin | `KMS` (AWS-generated — do NOT import external material; key-version rotation behavior differs) |
| Regionality | Single-Region |

**Why `us-east-1` only:** KMS calls are region-scoped and MySigner's IAM
principal is currently configured for `us-east-1`. Multi-region support is
not available today.

**Suggested alias:** `alias/mysigner-byok` (or anything you'll recognize in
your AWS console). MySigner does **not** use the alias — only the full ARN
— because aliases can be repointed after registration. The alias is purely
for your own bookkeeping.

### Option A: AWS Console

1. Sign in to your AWS account, switch to `us-east-1`.
2. Open **KMS** → **Customer managed keys** → **Create key**.
3. Step 1 — Configure key:
   - Key type: **Symmetric**
   - Key usage: **Encrypt and decrypt**
   - Advanced options → Key material origin: **KMS**
   - Advanced options → Regionality: **Single-Region key**
4. Step 2 — Add labels:
   - Alias: `mysigner-byok` (suggested)
   - Description: anything that helps you identify it later.
5. Step 3 — Define key administrative permissions: leave default (your AWS
   identity). MySigner does **not** need to be an admin.
6. Step 4 — Define key usage permissions: leave default for now. We'll
   paste the full key policy in Step 3 of this guide.
7. Step 5 — Review and finish.

### Option B: AWS CLI

```bash
aws kms create-key \
  --region us-east-1 \
  --description "MySigner BYOK CMK" \
  --key-usage ENCRYPT_DECRYPT \
  --key-spec SYMMETRIC_DEFAULT \
  --origin AWS_KMS
```

Capture the `KeyId` and `Arn` from the response — you'll need the ARN in
Step 3. Optionally attach an alias:

```bash
aws kms create-alias \
  --region us-east-1 \
  --alias-name alias/mysigner-byok \
  --target-key-id <key-id-from-create-key>
```

## Step 2 — Copy your CMK ARN

You need the **full ARN**, not an alias and not a bare key ID. Expected
format:

```
arn:aws:kms:us-east-1:<your-12-digit-account-id>:key/<uuid>
```

For example:

```
arn:aws:kms:us-east-1:111122223333:key/634b4e01-724e-4fdc-8c05-2a7dd833f1ce
```

Why a full ARN and not an alias or bare key ID:

- **Aliases resolve at call time.** Anyone with `kms:UpdateAlias` could
  repoint `alias/mysigner-byok` to a different key after MySigner verifies
  it — silently side-stepping our checks. The full ARN is bound to one
  specific key.
- **Bare key IDs** lose ownership context. Without the account ID in the
  ARN, our audit logs can't attribute KMS calls back to your AWS account
  if we ever need to support a forensic investigation.

Retrieve the ARN via Console (KMS → your CMK → **General configuration**
→ **ARN** field) or via CLI:

```bash
aws kms describe-key \
  --region us-east-1 \
  --key-id alias/mysigner-byok \
  --query 'KeyMetadata.Arn' \
  --output text
```

You'll paste this ARN into MySigner in Step 4. Step 3 (next) attaches the
key policy to the CMK itself — it does NOT need you to paste the ARN
anywhere, but you should keep the ARN handy while reading Step 3 because
it appears in MySigner's UI verification messages.

## Step 3 — Attach a key policy granting MySigner access

Paste the following key policy statement into your CMK's key policy.
Replace **two placeholders** before saving:

- `${MYSIGNER_AWS_ACCOUNT_ID}` — copy from the BYOK panel.
- `<your MySigner organization id>` — also copy from the BYOK panel.

```json
{
  "Sid": "AllowMySignerEnvelopeEncryption",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::${MYSIGNER_AWS_ACCOUNT_ID}:user/mysigner-app"
  },
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:EncryptionContext:org_id": "<your MySigner organization id>"
    }
  }
}
```

Merge this statement into your key policy's `Statement` array — alongside
the default `Enable IAM User Permissions` statement (which keeps your AWS
account's root user as the key administrator).

### Via Console

1. KMS → Customer managed keys → your CMK → **Key policy** tab.
2. Click **Switch to policy view**.
3. Add the statement above into the `Statement` array.
4. Click **Save changes**.

### Via CLI

```bash
aws kms put-key-policy \
  --region us-east-1 \
  --key-id <your-cmk-arn> \
  --policy-name default \
  --policy file://key-policy.json
```

Where `key-policy.json` is the full key policy document (your existing
default statement + the new one above).

### Why each clause is there

- **`Principal`** — identifies MySigner's IAM user (`mysigner-app`). This
  is the only principal we use for KMS calls on your CMK.
- **`Action` list** — only four operations. We deliberately do **not**
  request `kms:*` (which would let us schedule deletion of your key, or
  modify your key policy from our side) or `kms:CreateGrant` (which would
  let us delegate your CMK to other principals).
- **`Condition` on `kms:EncryptionContext:org_id`** — **critical.** This
  pins the grant to your org's data specifically. If MySigner is ever
  compromised, the attacker can't pivot your CMK against another
  customer's data: KMS itself rejects calls that don't carry your `org_id`
  in the encryption context.

We verify the condition exists via a deliberate **negative probe** at
register time (see Step 5). If your policy is missing the condition, the
negative probe succeeds (it shouldn't), and we refuse to save the ARN
until you fix it. MySigner's UI message in that case explicitly says
"see step 3 of the setup guide" — that's THIS step.

## Step 4 — Register the ARN in MySigner

1. Sign in to MySigner as an admin or owner.
2. Navigate to **Settings → Security → Bring Your Own Key**.
3. Paste your CMK ARN into the input field.
4. (Recommended) Click **Verify** first. This runs the same two probes
   that Save runs, but does **not** persist anything. Use it to confirm
   your key policy is correct before committing.
5. Click **Save**. We re-run the probes, register the ARN, and re-wrap all
   of your organization's existing credential envelopes with your CMK in
   the same atomic save.

The save emits a `byok_registered` audit event visible at
**Settings → Audit log**. The event metadata includes the registered ARN
and the per-credential-class rewrap counts so you can see exactly which
records were re-wrapped.

If anything fails, see "Common errors and how to fix them" below — and
note that any verify failure also emits a `byok_verify_failed` audit
event with the AWS error class and message attached.

## Step 5 — What "Verify" actually does

When you click Verify (or Save), MySigner runs two probes against your
CMK. Both are `kms:GenerateDataKey` calls; we discard the resulting data
keys — they're pure permission checks.

1. **Positive probe.** We ask KMS to generate a data key under your CMK
   with **your real `org_id`** in the encryption context. This should
   **succeed**. If it fails, your key policy isn't granting MySigner the
   access it needs.
2. **Negative probe.** We ask KMS to generate a data key under your CMK
   with a **deliberately wrong `org_id`** (the all-zeros UUID, which is
   guaranteed not to belong to any real organization). This should
   **fail with `AccessDeniedException`**. If it succeeds, your key policy
   is over-granting — the `kms:EncryptionContext:org_id` condition from
   Step 3 is missing, and any compromise of MySigner could pivot your CMK
   against other customers' data.

Both probes must pass for the registration to be accepted. Failure mapping
for the positive probe (these are the exact messages MySigner surfaces in
the UI):

| AWS error class | Likely cause | UI message |
|---|---|---|
| `NotFoundException` | ARN doesn't exist / in another region | "We couldn't find that CMK in us-east-1. Check the ARN and the region." |
| `AccessDeniedException` | Key policy doesn't grant our principal access | "Your key policy doesn't grant access to MySigner. See the BYOK setup guide." |
| `DisabledException` / `KMSInvalidStateException` | Key disabled or pending deletion | "Your CMK is disabled or pending deletion. Enable it before registering." |
| any other `Aws::KMS::Errors::ServiceError` | generic | Surface the message verbatim with a "contact support" link. |

If the **negative** probe SUCCEEDS, MySigner refuses to save the ARN and
shows: "Your key policy is missing the required `org_id` condition — see
step 3 of the setup guide." Step 3 above is the one to revisit.

We do **not** ask KMS for your full key policy (we'd need
`kms:GetKeyPolicy`, which is a privacy concern we deliberately avoid).
The two-probe technique gives us sufficient evidence without asking you
to grant us extra permissions.

## Rotation, migration, and clearing

### Rotating your CMK's key material

Standard AWS rotation (automatic or manual) is **transparent to MySigner**.
AWS retains old key versions and routes `kms:Decrypt` calls to the
correct version automatically. No MySigner action needed.

If you ever schedule deletion of an old key version while it still has
references, follow AWS's standard "don't delete old key material while
consumers reference it" guidance. MySigner doesn't track individual key
versions; we rely on AWS's version transparency.

### Migrating to a different CMK

1. Create the new CMK following Steps 1–3.
2. Attach the same key-policy statement (Step 3) to the new CMK.
3. In MySigner's BYOK panel, paste the **new** ARN and Save.

Internally we treat this as Clear + Register: we re-wrap your envelopes
back to the MySigner default CMK, then re-wrap them again with the new
CMK. The save emits both a `byok_cleared` and a `byok_registered` audit
event.

### Clearing BYOK

In the BYOK panel, click **Clear BYOK**. We re-wrap all your existing
credential envelopes back to the MySigner default CMK before nulling the
column — symmetric to register, so you can opt out cleanly. Emits a
`byok_cleared` audit event with the previous ARN and rewrap counts.

After clear, future writes go back to wrapping under MySigner's default
CMK — the same behavior as orgs that never registered BYOK.

## Revocation

When you remove MySigner's access to your CMK (by deleting the policy
statement, disabling the key, or scheduling deletion), here's what
happens on our side:

- The **next** envelope decrypt against your CMK raises
  `Aws::KMS::Errors::AccessDeniedException` (or
  `KMSInvalidStateException` for disabled / pending-deletion keys). We
  catch it as a `CustomerKeyRevoked` domain error.
- The Rails app returns the locked-copy message verbatim:

  > Your CMK is unreachable. Re-grant MySigner access or clear BYOK in
  > Settings → Security.

  HTML responses see this as a flash alert; JSON responses see a 403 with
  `{"error": "...", "code": "byok_key_revoked"}`.
- An in-flight **DEK cache** (1-hour TTL) on MySigner's side may continue serving cached
  decrypts for up to one hour after revocation. Full lockout takes effect
  after the cache expires. If you need immediate lockout (e.g. you're
  rotating in response to a compromise), contact MySigner support — we
  can purge the cache to enforce the lockout immediately.
- One **`byok_kms_key_revoked_detected`** audit event is emitted per org
  per 5-minute window (rate-limited to avoid log spam during a sustained
  outage).

To resume normal operation: either re-grant the key-policy statement
(Step 2 above), or click Clear BYOK to fall back to MySigner's default
CMK.

## Plan changes

BYOK is available to admin/owner on every plan tier (Free, Pro, Team).
Changing plans does not affect your BYOK configuration: the ARN stays
on the org row, your CMK keeps wrapping new writes, and you can update
or clear the ARN from the BYOK panel as before.

## Common errors and how to fix them

| Error message | What's wrong | What to do |
|---|---|---|
| "We couldn't find that CMK in us-east-1. Check the ARN and the region." | Either the ARN has a typo or the CMK lives in a different region. | Confirm the CMK is in `us-east-1` and re-copy the full ARN from the AWS console. |
| "Your key policy doesn't grant access to MySigner. See the BYOK setup guide." | The positive probe failed with `AccessDeniedException`. | Re-check the key-policy statement from Step 2. Verify the `Principal` ARN matches `arn:aws:iam::${MYSIGNER_AWS_ACCOUNT_ID}:user/mysigner-app` exactly (no typos in the account ID, no trailing whitespace). Verify the `Action` list contains all four operations. |
| "Your CMK is disabled or pending deletion. Enable it before registering." | KMS reports the key as disabled or scheduled for deletion. | In KMS, re-enable the key (or cancel the scheduled deletion). Re-run Verify. |
| "Your key policy is missing the required `org_id` condition — see step 3 of the setup guide." | The negative probe **succeeded** when it shouldn't have. The `kms:EncryptionContext:org_id` condition is missing from your key policy. | Re-edit the policy statement from Step 2 — confirm the `Condition` block is present and `<your MySigner organization id>` is filled in with the value from the BYOK panel. |
| "ARN must be a full KMS key ARN in us-east-1 (alias and bare key IDs are not accepted)." | You pasted an alias or a bare key ID instead of the full ARN. | Paste the full ARN — see Step 3. |
| "Verification could not complete: …" | Transient KMS error (rate-limited, regional issue, etc.). | Retry in a minute. If it persists, contact support. |

## What BYOK does not support today

1. **`us-east-1` only.** Customer CMKs in other regions aren't supported.
2. **One ARN per organization.** All four credential kinds (App Store
   Connect, Google Play, Android keystore, Apple Search Ads) wrap under
   the same CMK. Per-credential ARNs are not supported.
3. **Symmetric CMKs only.** Matches the envelope-encryption algorithm
   (AES-256-GCM). Asymmetric CMKs are not supported.
4. **No KMS grants.** We rely solely on your key policy. Grants would add
   another revocation surface; we keep the model simple and explicit.
5. **No automatic CMK rotation tracking.** AWS handles version
   transparency for `kms:Decrypt`; follow AWS's standard rotation
   guidance.

## Related

- AWS KMS documentation: <https://docs.aws.amazon.com/kms/>
