---
title: iOS to App Store
description: Submit your iOS app to the App Store for review and release
order: 3
---

# iOS to App Store

This guide walks you through submitting your iOS app to the App Store for review and distribution.

---

## Prerequisites

Before submitting to the App Store, ensure you have:

- **TestFlight tested build** - We recommend testing via TestFlight first
- **App Store Connect metadata** - App description, screenshots, keywords
- **App Store Connect credentials** configured in MySigner
- **Release configuration** set in the MySigner dashboard

> **First time?** Complete the [Getting Started](/docs/quickstart/getting-started) guide first.

---

## Step 1: Prepare Your Release in Dashboard

Before shipping, configure your release metadata in MySigner:

1. Go to the **MySigner dashboard**
2. Navigate to **iOS Apps** → Select your app
3. Click **New Release** or **Edit** existing release

### Configure Release Metadata

| Field | Description |
|-------|-------------|
| **What's New** | Release notes shown to users (localized) |
| **Version** | Version string (e.g., "1.2.0") |
| **Release Type** | How to release after approval |
| **Phased Release** | Gradual rollout to users |

### Release Types

| Type | Description |
|------|-------------|
| **Immediate** | Release as soon as approved |
| **Manual** | Hold for manual release after approval |
| **Scheduled** | Release at a specific date/time |

### Phased Release

Enable phased release to gradually roll out to users:

| Day | Percentage |
|-----|------------|
| 1 | 1% |
| 2 | 2% |
| 3 | 5% |
| 4 | 10% |
| 5 | 20% |
| 6 | 50% |
| 7 | 100% |

> **Tip:** Phased release lets you monitor for issues before full rollout. You can pause or halt the release if problems arise.

---

## Step 2: Verify App Store Readiness

Before submitting, check that your app is ready:

```bash
mysigner doctor
```

Ensure you have:

- ✓ App Store Connect credentials
- ✓ Valid distribution certificate
- ✓ App Store provisioning profile
- ✓ Bundle ID registered with correct capabilities

---

## Step 3: Ship to App Store

From your Xcode project directory:

```bash
mysigner ship appstore
```

This command:

1. **Builds** your app for distribution
2. **Exports** an IPA with App Store signing
3. **Uploads** to App Store Connect
4. **Waits** for Apple to process the build (polls every 3 minutes)
5. **Submits** for App Store review (creates version, applies release config, and submits)

### With Options

```bash
# Specify release type from CLI
mysigner ship appstore --release-type MANUAL

# Schedule release for a specific date
mysigner ship appstore --release-type SCHEDULED --scheduled-date 2026-04-01T10:00:00Z

# Specify scheme
mysigner ship appstore --scheme MyApp-Production
```

---

## Step 4: Monitor Submission

The CLI shows detailed progress:

```
🚀 My Signer - Ship to App Store
================================================================================

This will:
  1️⃣  Detect and build your project
  2️⃣  Export IPA for App Store
  3️⃣  Upload to App Store
  4️⃣  Wait for Apple to process build
  5️⃣  Submit for App Store review

⏱️  Estimated time: 15-30 minutes

================================================================================
[1/5] Building Archive
================================================================================

✓ Found: MyApp.xcworkspace (Native iOS)

🎯 Target: MyApp
📦 Bundle ID: com.company.myapp
⏱️  Estimated: 2-5 minutes

🔍 Validating signing setup...
✓ Signing configuration valid

Building archive...

✓ Build complete in 3m 12s

================================================================================
[2/5] Exporting IPA
================================================================================

⏱️  Estimated: 30-90 seconds

✓ Export complete in 52s
📦 IPA: ~/Archives/MyApp.ipa

================================================================================
[3/5] Uploading to App Store
================================================================================

🔐 Fetching App Store Connect credentials...
✓ Credentials loaded

Uploading to App Store Connect...
▸ Validating IPA
▸ Uploading... 52.1 MB / 52.1 MB (100%)
▸ Upload complete

================================================================================
[4/5] Waiting for Apple to Process Build
================================================================================

⏳ Waiting for build #43 to sync (polls every 3min)...
   [3m] Latest: #42, waiting for #43...
   [6m] Latest: #42, waiting for #43...
✅ Build #43 synced! (VALID)

================================================================================
[5/5] Submitting for App Store Review
================================================================================

✓ Submitted successfully

================================================================================
🎉 SUCCESS! Your app is submitted for App Store review!
================================================================================

📊 Summary

  Project:     MyApp
  Bundle ID:   com.company.myapp
  Target:      MyApp
  IPA Size:    52.1 MB

⏱️  Time Breakdown

  Build:       3m 12s
  Export:      52s
  Upload:      1m 23s
  Submission:  8m 45s
  ──────────────────────────────
  Total:       14m 12s

🔮 Next Steps

  ✓ Your build is submitted for App Store review!

  Monitor review status:
     https://appstoreconnect.apple.com/apps
```

> **Note:** App Review typically takes 24-48 hours. During busy periods (holidays, WWDC), reviews may take longer.

---

## Step 5: Track Review Status

### In App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Navigate to **My Apps** → Your app
3. Check the **App Store** tab for review status

### Review Statuses

| Status | Description |
|--------|-------------|
| Waiting for Review | In the review queue |
| In Review | Being reviewed by Apple |
| Pending Developer Release | Approved, waiting for you to release (Manual) |
| Pending Apple Release | Approved, waiting for scheduled date |
| Ready for Sale | Live on the App Store |
| Rejected | Issues need to be addressed |

---

## Step 6: Handle Review Outcomes

### If Approved

Your configured release type takes effect:

- **Immediate**: App goes live automatically
- **Manual**: Release from App Store Connect when ready
- **Phased**: Gradual rollout begins automatically

### If Rejected

1. **Read the rejection reason** carefully in App Store Connect
2. **Check Resolution Center** for detailed feedback
3. **Fix the issues** in your app or metadata
4. **Resubmit** using `mysigner ship appstore`

Common rejection reasons:

| Reason | Solution |
|--------|----------|
| Guideline 2.1 - Crashes | Test thoroughly, check crash logs |
| Guideline 2.3 - Incomplete | Ensure demo accounts if login required |
| Guideline 4.2 - Minimum Functionality | Add more features or content |
| Guideline 5.1.1 - Privacy | Add/update privacy policy |

---

## Workflow Diagram

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Configure  │────▶│    Build &   │────▶│   Upload &   │
│   Release    │     │    Export    │     │   Process    │
└──────────────┘     └──────────────┘     └──────────────┘
                                                 │
                                                 ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Release    │◀────│   Approved   │◀────│   Submit &   │
│   to Users   │     │   by Apple   │     │   Review     │
└──────────────┘     └──────────────┘     └──────────────┘
```

---

## Time Estimates

| Phase | Duration |
|-------|----------|
| Build & Export | 3-7 minutes |
| Upload | 1-3 minutes |
| Processing | 10-20 minutes |
| App Review | 24-48 hours (typically) |
| **Total to Submission** | **15-30 minutes** |

> **Note:** Review times vary. During busy periods (holidays, WWDC), reviews may take longer.

---

## Best Practices

### Before Submission

1. **Test on TestFlight** with real users
2. **Check analytics** for crashes or issues
3. **Update all metadata** - screenshots, description, keywords
4. **Verify privacy labels** are accurate
5. **Test in-app purchases** if applicable

### Release Strategy

1. **Use phased release** for major updates
2. **Monitor crash rates** during rollout
3. **Prepare to pause** if issues arise
4. **Have a hotfix ready** just in case

### Expedited Reviews

For critical bug fixes, request an expedited review:

1. Go to App Store Connect
2. Navigate to your pending submission
3. Click "Request Expedited Review"
4. Explain the critical issue

---

## Common Issues

### "Version already exists"

You're trying to submit the same version number that's already live or pending.

**Fix:** Increment your version number in Xcode or Info.plist.

### "Missing compliance information"

Export compliance declaration needed.

**Fix:** 
1. In App Store Connect, go to your build
2. Click "Provide Export Compliance Information"
3. Answer the encryption questions

### "Missing required screenshots"

Screenshot requirements not met for all device sizes.

**Fix:** Upload screenshots for required device sizes in App Store Connect.

### Build stuck in "Processing"

Processing usually takes 10-20 minutes.

**Fix:** Wait up to 1 hour. If still stuck, contact Apple Developer Support.

---

## Next Steps

- [GitHub Actions CI/CD](/docs/guides/ci-cd-github) - Automate App Store submissions
- [Troubleshooting](/docs/guides/troubleshooting) - More issue solutions
- [Dashboard Releases](/docs/dashboard/releases) - Configure release settings

---

## Related Commands

- [`ship`](/docs/commands/ship) - Full ship command reference
- [`submit`](/docs/commands/submit) - Submit without building
- [`doctor`](/docs/commands/doctor) - Diagnose issues
- [`sync`](/docs/commands/sync) - Refresh App Store Connect data

## Related Dashboard Pages

- [Releases](/docs/dashboard/releases) - Configure release notes, run the AI translate / rewrite workflow, manage the release checklist before submission
- [Screenshot Studio](/docs/dashboard/screenshot-studio) - Generate App Store screenshots and push them straight to App Store Connect
- [Keywords & ASO](/docs/dashboard/keywords) *(Pro+)* - Edit the 100-character keywords field per locale and track ranking positions
- [Custom Product Pages](/docs/dashboard/custom-product-pages) *(Pro+)* - Build CPP variants for marketing campaigns or A/B testing
- [Reviews & Ratings](/docs/dashboard/reviews) - Reply to reviews and use response templates after release
- [Analytics](/docs/dashboard/analytics) - Measure release impact (acquisition, retention, conversion)
