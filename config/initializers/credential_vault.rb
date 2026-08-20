# Boot-time check: in production we MUST have a KMS key ARN configured.
# Without it, the Vaulted concern silently no-ops and credential envelopes
# never get written — that's a security regression we want to catch at boot,
# not at the first credential write hours later.
#
# Test and development environments are allowed to boot without KMS; tests
# that need vault behavior set CredentialVault.kms_client + key_arn explicitly.
#
# Skip during Docker image builds. The Dockerfile runs
# `SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile` to bake the asset
# pipeline into the image WITHOUT real runtime secrets — KMS env vars aren't
# available yet at build time; they get injected at container start by Kamal.
# `SECRET_KEY_BASE_DUMMY` is the Rails-idiomatic "I'm a dummy build, skip
# requirements that only matter at actual server boot" signal.

Rails.application.config.after_initialize do
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  if Rails.env.production? && !CredentialVault.configured?
    raise "MYSIGNER_KMS_KEY_ARN env var must be set in production (CredentialVault is unconfigured)"
  end
end
