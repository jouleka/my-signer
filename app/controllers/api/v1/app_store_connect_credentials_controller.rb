module Api
  module V1
    class AppStoreConnectCredentialsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :require_user_email!
      before_action :verify_write_or_admin_scope

      # POST /api/v1/organizations/:organization_id/app_store_connect_credentials
      def create
        return if performed?

        authorize @organization, :manage_credentials?

        validator = AppStoreConnect::CredentialValidator.new(
          key_id: credential_params[:key_id],
          issuer_id: credential_params[:issuer_id],
          private_key: credential_params[:private_key]
        )

        validation = validator.validate!

        credential = @organization.app_store_connect_credentials.new(credential_params)
        credential.team_id ||= validation.team_id

        # Auto-activate only if this is the first credential for the organization
        is_first_credential = @organization.app_store_connect_credentials.count == 0
        credential.active = is_first_credential

        if credential.save
          credential.activate_exclusively! if credential.active?
          credential.reload
          trigger_initial_sync_if_needed(credential)
        else
          raise ActiveRecord::RecordInvalid.new(credential)
        end

        Audit::Logger.log(
          organization: @organization,
          actor:        current_user,
          action:       "asc_credential_added",
          resource:     credential,
          request:      request,
          metadata: {
            credential_id: credential.id,
            name:          credential.name,
            key_id:        credential.key_id,
            team_id:       credential.team_id,
            active:        credential.active
          }
        )

        render json: credential_response(credential, validation), status: :created
      rescue AppStoreConnect::CredentialValidator::ValidationError => e
        render_external_error("Apple validation failed: #{sanitize_error_message(e)}")
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def credential_params
        permitted = params[:app_store_connect_credential] || params
        permitted.permit(:name, :key_id, :issuer_id, :private_key, :team_id)
      end

      def credential_response(credential, validation)
        {
          id: credential.id,
          name: credential.name,
          key_id: credential.key_id,
          issuer_id: credential.issuer_id,
          team_id: credential.team_id,
          active: credential.active,
          created_at: credential.created_at.iso8601,
          validation: {
            success: true,
            team_id: credential.team_id,
            sources: validation.sources
          }
        }
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      def trigger_initial_sync_if_needed(credential)
        return false unless credential.active?
        return false unless policy(@organization).sync?
        return false unless @organization.scheduled_sync_enabled?

        AppStoreConnectSyncJob.perform_later(@organization.id)
        true
      rescue => e
        Rails.logger.error("Failed to enqueue initial ASC sync for org #{@organization.id}: #{e.message}")
        false
      end
    end
  end
end
