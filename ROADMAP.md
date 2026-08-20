# Roadmap

This roadmap reflects the current pre-Paddle state of My Signer.

## Current State

- Pricing v1 is live with `free`, `pro`, and `team` entitlements.
- Backend enforcement is the source of truth for owned org caps, seats and invites, screenshot project limits, storage and upload quotas, and store-upload gating.
- The web app shows upgrade prompts and plan-aware gating for org creation, invites, and screenshot flows.
- Upgrades are still manual. Paddle Checkout and billing management are not integrated yet.

## Next

- Build self-serve billing with Paddle Checkout.
- Add Paddle Customer Portal support for billing management.
- Sync subscription state back into the app via webhooks.
- Wire pricing and upgrade flows to real billing actions.

## After Paddle

- Expose billing state and usage more clearly in the dashboard.
- Add CLI polish for billing, plan status, and quota guidance once billing flows are stable.
