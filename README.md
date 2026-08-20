# My Signer

**One CLI command from code to TestFlight or Google Play. No provisioning hell, no manual certificate wrangling.**

---

## 📚 Documentation

- **[ROADMAP.md](ROADMAP.md)** - Current pre-Paddle roadmap and next milestones
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development workflow and pull-request checks
- **[SECURITY.md](SECURITY.md)** - How to report vulnerabilities privately
- **`app/views/docs`** - Source for the in-app documentation site

---

## What is My Signer?

My Signer is a modern developer tool that eliminates "Provisioning Profile Hell" for iOS and Android developers. It provides:

1. **Web Dashboard** - Visual interface to manage certificates, devices, profiles, and keystores
2. **CLI Tool** - Automate signing and deployment from the command line
3. **API** - Integrate with your CI/CD pipeline

### The Problem We Solve

Mobile app deployment is frustrating:
- ❌ Manual certificate and keystore management
- ❌ Confusing provisioning profile errors
- ❌ Tedious device registration
- ❌ Complex TestFlight and Google Play upload processes
- ❌ Time wasted navigating Apple Developer Portal and Play Console
- ❌ Version code conflicts on Google Play

### Our Solution

✅ **Visual Dashboard** - See all signing assets at a glance (iOS + Android)
✅ **One-Command Deploy** - `mysigner ship testflight` or `mysigner ship production --platform android`
✅ **Automatic Profile Matching** - No more "Code signing is required" errors
✅ **Smart Version Handling** - Auto-increment version codes for Android
✅ **Team Collaboration** - Share profiles, certificates, and keystores securely
✅ **Plan-Aware Gating** - Free, Pro, and Team entitlements enforced in the dashboard and API

---

## Features

### Web Dashboard
- 📊 Overview of all certificates, devices, profiles, and keystores
- 🍎 **iOS**: Certificates, devices, provisioning profiles, bundle IDs
- 🤖 **Android**: Keystores, apps, builds, track configuration
- 💳 **Pricing**: Free, Pro, and Team plans with manual upgrade flow before Paddle
- 🔍 Search and filter resources
- 📥 Download provisioning profiles and keystores
- ➕ Register test devices instantly
- ⚙️ App Store Release configuration (release type, phased release, metadata)
- 🧱 Upgrade prompts for org creation, invites, screenshot projects, and store uploads
- 🎨 Beautiful, responsive UI (DaisyUI + TailwindCSS)

### CLI ✅ Fully Functional
- 🚀 **Build & Ship**: `mysigner ship testflight`, `mysigner ship appstore`
- 🤖 **Android Deploy**: `mysigner ship internal/alpha/beta/production --platform android`
- 🔐 Secure API token authentication
- 📱 Device registration: `mysigner device add "iPhone" UDID`
- 📥 Profile download: `mysigner profile download ID`
- 🔑 Keystore management: `mysigner keystore upload/download/activate`
- 🔑 Google Play credentials: `mysigner gp-credential list/activate/test`
- 📜 Certificate management: `mysigner certificates`
- 🚀 Release configuration: `mysigner release list/create/update`
- 🔍 Signing validation: `mysigner validate`
- 🩺 Health check: `mysigner doctor` (auto-fixes common issues)
- 🔄 Sync: `mysigner sync` (iOS), `mysigner sync android`
- 📦 25+ working commands
- 🚀 260+ automated tests

### API
- 🔒 Token-based authentication
- 📡 RESTful endpoints for all resources (24+ controllers)
- 📖 OpenAPI 3.0 specification
- ⚡ Fast response times (<100ms average)
- 🔐 Rate limiting (100 req/min per token)

---

## Tech Stack

**Backend**:
- Ruby on Rails 8.0
- PostgreSQL 16
- Solid Queue (background jobs)
- Solid Cache & Solid Cable

**Frontend**:
- Hotwire (Turbo + Stimulus)
- TailwindCSS + DaisyUI

**Integrations**:
- App Store Connect API (JWT auth)
- Google Play Developer API (Service Account)

**Deployment**:
- Docker
- Kamal

---

## Getting Started

### Prerequisites
- Ruby 3.2+
- PostgreSQL 16+
- Redis 7+
- Apple Developer Account
- `libvips` for screenshot thumbnail variants in local development (`brew install vips` on macOS)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/jouleka/my-signer.git
   cd my-signer
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

   For local screenshot thumbnail processing, install `libvips` as well:
   ```bash
   brew install vips
   ```

3. **Setup database**
   ```bash
   bin/rails db:create db:migrate
   ```

4. **Start the server**
   ```bash
   bin/dev
   ```

5. **Visit the app**
   ```
   http://localhost:3000
   ```

### First Steps

1. **Sign up** for an account
2. **Create an organization** if your plan allows another owned org
3. **Add App Store Connect credentials** (API Key) for iOS
4. **Add Google Play credentials** (Service Account) for Android
5. **Run your first sync** to fetch certificates, devices, profiles, and apps
6. **Start managing** your signing assets!

> **Pricing note:** My Signer currently ships with `free`, `pro`, and `team` entitlements. Upgrade prompts and plan limits are live in the product today, but upgrades are still handled manually until Paddle Checkout and the billing portal are integrated.

### CLI Quick Start

```bash
# Install the CLI
gem install mysigner

# Login and configure
mysigner onboard

# Ship your app!
mysigner ship testflight                      # iOS to TestFlight
mysigner ship appstore                        # iOS to App Store
mysigner ship production --platform android   # Android to Production
```

---

## Project Status

**Current Phase**: Pricing v1 complete, Paddle billing next

✅ **Completed**:
- ✅ Web dashboard for managing iOS + Android signing assets
- ✅ App Store Connect API integration
- ✅ Google Play Developer API integration
- ✅ Background sync workers (Solid Queue)
- ✅ Device registration
- ✅ Provisioning profile creation
- ✅ Android keystore management
- ✅ API token authentication
- ✅ **Complete REST API** (24+ controllers)
- ✅ OpenAPI 3.0 specification
- ✅ Swagger UI interactive documentation
- ✅ Rate limiting (100 req/min per token)
- ✅ Standardized error responses
- ✅ CORS support
- ✅ **Complete CLI Tool** (`my-signer-cli` gem)
  - 25+ commands (auth, build, ship, submit, sync, doctor, validate, release, gp-credential, etc.)
  - iOS: `mysigner ship testflight`, `mysigner ship appstore`
  - Android: `mysigner ship internal/alpha/beta/production`
  - 260+ RSpec tests
  - Project detection (Native, React Native, Flutter, Capacitor)
  - Auto version code increment for Android
- ✅ App Store submission with release types (AFTER_APPROVAL, MANUAL, SCHEDULED)
- ✅ App Store Release configuration in dashboard
- ✅ Pricing entitlements for `free`, `pro`, and `team`
- ✅ Backend enforcement for org caps, seats/invites, screenshot projects, storage/upload limits, and store-upload gating
- ✅ Shared upgrade prompts and pricing-aware dashboard gating
- ✅ Manual upgrade flow and pricing page while self-serve billing is still pending

📅 **Future**:
- Paddle Checkout for self-serve upgrades
- Paddle Customer Portal for billing management
- Webhook-driven subscription syncing
- Billing status, cancel, downgrade, and usage surfaces
- CLI pricing/quota polish after billing is live

See [ROADMAP.md](ROADMAP.md) for detailed plans.

---

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change.

---

## License

Licensed under the [Apache License 2.0](LICENSE).

---

## Support

For questions or issues:
- Check the in-app docs under `app/views/docs`
- See [ROADMAP.md](ROADMAP.md) for the current roadmap
- Open a GitHub issue for reproducible bugs and feature proposals
- Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md)

---

## Why "My Signer"?

Because managing mobile app signing should be **yours to control**, not a source of frustration. We're building the tool we wish existed when we started mobile development.

**Target Users**:
- 🧑‍💻 Indie iOS and Android developers
- 🏢 Small development teams
- 🎯 Agencies managing multiple apps
- 🚀 Anyone tired of provisioning profile errors and keystore headaches
- 🔄 Cross-platform developers (React Native, Flutter, Capacitor)

---

**Built with ❤️ by developers who hate provisioning profile hell.**
