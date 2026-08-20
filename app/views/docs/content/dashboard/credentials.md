---
title: Credentials
description: Set up App Store Connect and Google Play credentials
order: 2
---

## Overview

MySigner needs API credentials to interact with App Store Connect and Google Play Console on your behalf. This guide walks you through setting up both.

## App Store Connect Credentials

### Create an API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api)
2. Click **Generate API Key** (requires Admin or App Manager role)
3. Give it a name like "MySigner"
4. Select **App Manager** or **Admin** role
5. Click **Generate**
6. **Download the `.p8` file immediately** - you can only download it once!
7. Note the **Key ID** and **Issuer ID** shown on the page

> **Warning:** Store your `.p8` file securely. If you lose it, you'll need to generate a new key.

### Add to MySigner

1. In the MySigner dashboard, go to your organization
2. Click **Add App Store Connect Credential**
3. Enter:
   - **Name** - A descriptive name (e.g., "Production API Key")
   - **Key ID** - The 10-character identifier from ASC
   - **Issuer ID** - The UUID from ASC (looks like `69a6de7e-...`)
   - **Private Key** - Paste the entire contents of your `.p8` file
4. Click **Save**

### Test the Connection

After saving, click **Test** to verify the credential works. MySigner will:

- Authenticate with App Store Connect
- Retrieve your Team ID
- List available apps

If successful, you'll see a green checkmark and your Team ID will be displayed.

### Activate the Credential

If you have multiple credentials, click **Activate** to set one as the default for this organization.

## Google Play Credentials

### Create a Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Select or create a project
3. Click **Create Service Account**
4. Enter:
   - **Name** - "MySigner"
   - **ID** - Auto-generated
   - **Description** - "MySigner app deployment"
5. Click **Create and Continue**
6. Skip the role assignment (we'll do this in Play Console)
7. Click **Done**

### Generate a Key

1. Click on the service account you just created
2. Go to **Keys** tab
3. Click **Add Key** → **Create new key**
4. Select **JSON** format
5. Click **Create**
6. Save the downloaded JSON file securely

### Grant Access in Play Console

1. Go to [Google Play Console](https://play.google.com/console)
2. Click **Users and permissions** → **Invite new users**
3. Paste the service account email (ends in `@...iam.gserviceaccount.com`)
4. Grant these permissions:
   - **Release apps to testing tracks**
   - **Release to production, exclude devices, and use Play App Signing**
   - **View app information and download bulk reports**
5. Click **Invite user**
6. Click **Apply** on the app(s) you want to deploy

> **Note:** It may take a few minutes for permissions to propagate.

### Add to MySigner

1. In the MySigner dashboard, go to your organization
2. Click **Add Google Play Credential**
3. Enter:
   - **Name** - A descriptive name
   - **Developer Account ID** *(optional)* - Found in Play Console under Account details
   - **Service Account JSON** - Paste the entire JSON file contents
4. Click **Save**

### Test the Connection

Click **Test** to verify. MySigner will:

- Authenticate with Google Play
- List available apps
- Verify write permissions

## Multiple Credentials

You can add multiple credentials per organization, which is useful for:

- **Separate teams** - Different credentials for different apps
- **Rotation** - Add a new key before expiring the old one
- **Testing** - Use a read-only key for testing

Only one credential can be **active** at a time per provider (ASC or Google Play). The active credential is used by default for CLI commands.

## Security Best Practices

1. **Minimal permissions** - Only grant the permissions MySigner needs
2. **Rotate regularly** - Generate new keys periodically
3. **Audit access** - Review who has access to credentials. On Team plans, every credential add / activate / remove event is recorded in the [Audit Log](/docs/dashboard/audit-log) so you have a full history of who changed what and when.
4. **Revoke unused** - Delete credentials you no longer need
5. **Never share** - Don't send credentials via email or chat

## Related

- [Organizations](/docs/dashboard/organizations) - Create and manage organizations
- [API Tokens](/docs/dashboard/api-tokens) - CLI authentication
- [iOS Resources](/docs/dashboard/ios-resources) - Manage certificates and profiles
- [Android Resources](/docs/dashboard/android-resources) - Manage keystores and apps
- [Audit Log](/docs/dashboard/audit-log) - Track credential changes *(Team)*
- [Notifications](/docs/dashboard/notifications) - Alerts for sync failures and revocations
- [Getting Started](/docs/quickstart/getting-started) - Initial setup
