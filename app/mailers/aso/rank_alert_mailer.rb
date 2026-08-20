module Aso
  class RankAlertMailer < ApplicationMailer
    # Weekly keyword-rank digest for Team-tier orgs. `movements` is a list of
    # Aso::RankMovement instances that already passed the #significant? gate
    # in Aso::RankAlertDigestJob — the mailer itself does no filtering; it
    # just renders whatever the caller hands it (including an empty list,
    # which renders a friendly "nothing moved this week" body).
    def weekly_digest(user:, organization:, movements:)
      @user = user
      @organization = organization
      @movements = movements

      # Header-injection hardening: take only the first line of the org name
      # (drop anything after CR/LF — an attacker can't smuggle "Bcc:" or any
      # other header since everything after the break is discarded) and clamp
      # length so a giant org name can't produce an RFC 5322 line too long to
      # deliver.
      safe_org_name = organization.name.to_s.split(/[\r\n]/).first.to_s.strip.truncate(80)

      mail(
        to: user.email,
        subject: "[MySigner] Weekly keyword rank changes for #{safe_org_name}"
      )
    end
  end
end
