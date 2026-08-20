# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability or include credentials, tokens, signing keys, customer data, or exploit details in an issue.

Use GitHub's **Security** tab and select **Report a vulnerability** to send a private report. Include the affected version or commit, a minimal reproduction, impact, and any suggested mitigation. You should receive an acknowledgement within five business days.

## Supported version

Security fixes are applied to the latest commit on `main`. The hosted service may be updated ahead of a tagged source release.

## Credential handling

Never commit `.env` files, Rails master keys, Apple private keys, Android keystores, Google service-account JSON, cloud credentials, or deployment secrets. Use the environment and encrypted/local secret stores described in the documentation.
