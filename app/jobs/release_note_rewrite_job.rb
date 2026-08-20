class ReleaseNoteRewriteJob < ApplicationJob
  queue_as :default

  # Rewrites raw changelog text into polished release notes using AI.
  #
  # @param organization_id [Integer]
  # @param release_note_id [Integer] The release note to update
  # @param raw_input [String] Raw technical changelog text
  def perform(organization_id:, release_note_id:, raw_input:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    release_note = organization.release_notes.find_by(id: release_note_id)
    return unless release_note

    # Optimistic decrement: check quota and increment counter under lock,
    # then release lock before making the slow OpenAI API call.
    can_rewrite = false
    organization.with_lock do
      entitlements = organization.entitlements
      remaining = entitlements.ai_rewrites_remaining(organization)
      if remaining <= 0
        Rails.logger.warn("ReleaseNoteRewriteJob: Rewrite limit reached for org #{organization_id}")
      else
        organization.increment!(:ai_rewrites_count)
        can_rewrite = true
      end
    end

    return unless can_rewrite

    # Rewrite outside the lock — no DB lock held during network I/O
    begin
      ReleaseNotes::AiRewriter.new(
        release_note: release_note,
        raw_input: raw_input
      ).rewrite!
    rescue StandardError => e
      # Rollback the quota consumed for a failed rewrite
      organization.with_lock do
        organization.reload
        organization.decrement!(:ai_rewrites_count) if organization.ai_rewrites_count > 0
      end
      raise
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("ReleaseNoteRewriteJob: Record not found - #{e.message}")
  rescue StandardError => e
    Rails.logger.error("ReleaseNoteRewriteJob failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    raise
  end
end
