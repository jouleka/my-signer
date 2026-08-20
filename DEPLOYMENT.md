# Deployment

My Signer ships with a Kamal configuration for deploying the Rails application and PostgreSQL accessory to a Linux host. The repository deliberately contains no production addresses, SSH keys, registry credentials, Rails keys, or cloud credentials.

## Requirements

- A Linux server reachable over SSH
- Docker installed on the server
- A container registry and access token
- Ruby and Bundler locally
- DNS for the hostname configured in `config/deploy.yml`

## Required environment

Set these non-secret deployment coordinates in your shell or CI environment:

```bash
export DEPLOY_HOST="server.example.com"
export KAMAL_IMAGE="registry-user/my-signer"
export KAMAL_REGISTRY_USERNAME="registry-user"
```

Kamal reads secret values through `.kamal/secrets`. Store the referenced raw values in `.kamal/secrets.d/` and the Rails/OpenAI keys under `config/credentials/`; all of those paths are ignored by Git. Never put real values in `config/deploy.yml`, `.kamal/secrets`, documentation, or workflow files.

At minimum, configure the registry token, Rails production key, PostgreSQL password, Active Record Encryption keys, and any integration credentials used by your deployment. Generate fresh values for a new installation; do not copy credentials from another environment.

## Deploy

Review the host, image, proxy hostname, storage, database, billing, and encryption settings before the first deployment. Then run:

```bash
bundle install
bin/kamal config
bin/kamal setup
```

Subsequent releases use:

```bash
bin/kamal deploy
```

Useful read-only checks include `bin/kamal app details` and `bin/kamal accessory details db`.

## GitHub Actions

The repository workflow will deploy from `main` only when the repository variable `DEPLOY_ENABLED` is exactly `true`. Leave it unset during forks, migrations, and initial setup.

The workflow expects:

- repository variables `KAMAL_IMAGE` and `KAMAL_REGISTRY_USERNAME`
- secret `DEPLOY_HOST`
- secret `SSH_PRIVATE_KEY`
- secret `SSH_KNOWN_HOSTS` containing a previously verified host-key entry
- the application and infrastructure secrets referenced by `.github/workflows/ci.yml`

Do not replace `SSH_KNOWN_HOSTS` with an unauthenticated `ssh-keyscan` during a deployment; verify the server fingerprint through your hosting provider or another trusted channel first.

## Backups and rollback

Before the first production deployment, configure encrypted database and Active Storage backups outside the application host and test restoring them. Kamal can roll back application containers, but it does not replace database or object-storage backups.
