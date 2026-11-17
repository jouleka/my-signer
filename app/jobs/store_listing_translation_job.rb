class StoreListingTranslationJob < ApplicationJob
  include SanitizesErrorMessage

  queue_as :default

  def perform(organization_id:, store_listing_id:, base_listing_id:, fields: "all", operation_id: nil)
    organization = Organization.find_by(id: organization_id)
    target = organization&.store_listings&.find_by(id: store_listing_id)
    return unless target
    return if operation_id && target.metadata["translation_operation_id"] != operation_id

    charged = false
    begin
      base = target.listable.store_listings.find_by(id: base_listing_id)
      raise "Cannot translate: invalid source listing." unless base && base.id != target.id

      organization.with_lock do
        unless organization.entitlements.ai_translations_remaining(organization) > 0
          raise "You've reached your monthly AI translation limit."
        end
        organization.increment!(:ai_translations_count)
        charged = true
      end

      field_list = fields == "all" ? :all : fields.split(",").map(&:strip).map(&:to_sym)
      StoreListingSync::AiTranslator.new(base_listing: base, target_listing: target, fields: field_list).translate!
    rescue StandardError => error
      if charged
        organization.with_lock do
          organization.decrement!(:ai_translations_count) if organization.ai_translations_count > 0
        end
      end
      target.with_lock do
        target.update!(translation_status: "failed",
          metadata: target.metadata.merge("translation_error" => sanitize_error_message(error)))
      end
      raise
    ensure
      # Notification failure must not refund a completed translation or hide its result.
      begin
        target.trigger_live_refresh
      rescue StandardError => error
        Rails.logger.warn("StoreListingTranslationJob refresh failed: #{error.class}")
      end
    end
  end
end
