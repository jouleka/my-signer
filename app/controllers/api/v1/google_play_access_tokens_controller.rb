module Api
  module V1
    class GooglePlayAccessTokensController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :require_user_email!
      # Admin scope: this endpoint mints a short-lived Google Play OAuth token
      # that is returned to the caller. The removed GET /organizations/:id/credentials
      # required admin scope for the same material; keep it that way so a
      # compromised write-only token cannot mint publishing tokens.
      before_action :verify_admin_scope!

      # POST /api/v1/organizations/:organization_id/credentials/google_play/access_token
      def create
        authorize @organization, :manage_credentials?

        credential = @organization.google_play_credentials.where(active: true).first
        return render_not_found("Active Google Play credential") unless credential

        payload = GooglePlay::TokenMinter.mint(credential)

        Audit::Logger.log(
          organization: @organization,
          actor: current_user,
          action: "credential_read_google_play_token",
          request: request,
          metadata: {
            credential_id:   credential.id,
            credential_name: credential.name,
            cache_hit:       payload[:cache_hit],
            outcome:         "ok"
          }
        )

        render json: {
          access_token:         payload[:access_token],
          expires_at:           payload[:expires_at]&.iso8601,
          client_email:         payload[:client_email],
          developer_account_id: payload[:developer_account_id]
        }
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end
    end
  end
end
