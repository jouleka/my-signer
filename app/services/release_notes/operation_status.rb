module ReleaseNotes
  # Persist the state alongside the note so failures and queued work survive reload.
  class OperationStatus
    def initialize(note)
      @note = note
    end

    def start!(kind)
      @note.with_lock do
        return if @note.ai_pending?
        raise "This release note cannot be edited." unless @note.content_editable?
        id = SecureRandom.uuid
        @note.update!(metadata: @note.metadata.merge("ai_operation" => {
          "id" => id, "kind" => kind, "status" => "pending", "started_at" => Time.current.iso8601
        }))
        id
      end
    end

    def current?(id)
      id.nil? || (@note.metadata.dig("ai_operation", "id") == id && @note.ai_pending?)
    end

    def claim!(id)
      return true unless id
      @note.with_lock do
        return false unless current?(id) && @note.metadata.dig("ai_operation", "status") == "pending"
        operation = @note.metadata.fetch("ai_operation").merge("status" => "running")
        @note.update!(metadata: @note.metadata.merge("ai_operation" => operation))
        true
      end
    end

    def finish!(id, error: nil)
      return unless id
      # A failed content validation can leave this instance dirty. Reload the
      # persisted note before recording the failure so retry remains available.
      @note.reload.with_lock do
        return unless @note.metadata.dig("ai_operation", "id") == id
        operation = @note.metadata.fetch("ai_operation").merge(
          "status" => error ? "failed" : "completed", "error" => error && ErrorMessageSanitizer.sanitize(error),
          "finished_at" => Time.current.iso8601
        )
        @note.update!(metadata: @note.metadata.merge("ai_operation" => operation))
      end
      refresh
    end

    def refresh
      @note.trigger_live_refresh
    rescue StandardError => e
      Rails.logger.warn("Release note refresh failed: #{e.class}")
    end
  end
end
