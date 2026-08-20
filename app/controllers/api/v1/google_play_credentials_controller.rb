module Api
  module V1
    class GooglePlayCredentialsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :require_user_email!
      before_action :set_credential, only: [ :destroy, :activate, :test ]
      before_action :verify_read_scope, only: [ :index ]
      before_action :verify_write_or_admin_scope, only: [ :create, :destroy, :activate, :test ]

      # GET /api/v1/organizations/:organization_id/google_play_credentials
      def index
        authorize @organization, :show?

        creds = @organization.google_play_credentials.order(created_at: :desc)

        render json: {
          google_play_credentials: creds.map { |c| credential_json(c) }
        }
      end

      # POST /api/v1/organizations/:organization_id/google_play_credentials
      def create
        authorize @organization, :manage_credentials?

        is_first_credential = !@organization.google_play_credentials.exists?
        credential = @organization.google_play_credentials.new(credential_params)
        credential.active = true if is_first_credential

        if credential.save
          credential.activate_exclusively! if credential.active?
          trigger_initial_sync_if_needed(credential)

          Audit::Logger.log(
            organization: @organization,
            actor:        current_user,
            action:       "google_play_credential_added",
            resource:     credential,
            request:      request,
            metadata: {
              credential_id:        credential.id,
              name:                 credential.name,
              developer_account_id: credential.developer_account_id,
              active:               credential.active
            }
          )

          render json: credential_json(credential), status: :created
        else
          render_validation_failed("Failed to create Google Play credential", details: credential.errors.full_messages)
        end
      end

      # DELETE /api/v1/organizations/:organization_id/google_play_credentials/:id
      def destroy
        authorize @organization, :manage_credentials?

        @credential.destroy
        render json: { message: "Credential deleted" }, status: :ok
      end

      # POST /api/v1/organizations/:organization_id/google_play_credentials/:id/activate
      def activate
        authorize @organization, :manage_credentials?
        @credential.activate_exclusively!
        trigger_initial_sync_if_needed(@credential)
        render json: credential_json(@credential), status: :ok
      end

      # POST /api/v1/organizations/:organization_id/google_play_credentials/:id/test
      def test
        authorize @organization, :manage_credentials?
        begin
          client = GooglePlay::Client.new(credential: @credential)
          client.ping!
          render json: { message: "Google Play connection successful" }, status: :ok
        rescue => e
          render_external_error("Google Play connection test failed: #{sanitize_error_message(e)}")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_credential
        @credential = @organization.google_play_credentials.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Credential")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      def trigger_initial_sync_if_needed(credential)
        return false unless credential.active?
        return false unless policy(@organization).sync?
        return false unless @organization.scheduled_sync_enabled?

        GooglePlaySyncJob.perform_later(@organization.id)
        true
      rescue => e
        Rails.logger.error("Failed to enqueue initial Google Play sync for org #{@organization.id}: #{e.message}")
        false
      end

      def credential_params
        # Accept plain attributes or nested under :google_play_credential
        permitted = params[:google_play_credential] || params
        permitted.permit(:name, :service_account_json, :developer_account_id, :active)
      end

      def credential_json(c)
        {
          id: c.id,
          name: c.name,
          developer_account_id: c.developer_account_id,
          active: c.active,
          last_synced_at: c.last_synced_at&.iso8601,
          last_sync_status: c.last_sync_status,
          created_at: c.created_at.iso8601,
          updated_at: c.updated_at.iso8601
        }
      end
    end
  end
end
