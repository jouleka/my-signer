module Api
  module V1
    class AndroidKeystoreSecretsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :require_user_email!
      # Admin scope: this endpoint returns raw keystore / key passwords.
      # The removed GET /organizations/:id/credentials required admin scope
      # for the same material; keep it that way so a compromised write-only
      # token cannot pull signing secrets.
      before_action :verify_admin_scope!
      before_action :set_keystore

      # POST /api/v1/organizations/:organization_id/android_keystores/:id/secrets
      def create
        authorize @organization, :manage_credentials?

        Audit::Logger.log(
          organization: @organization,
          actor: current_user,
          action: "credential_read_android_keystore_secrets",
          request: request,
          metadata: {
            credential_id:   @keystore.id,
            credential_name: @keystore.name,
            outcome:         "ok"
          }
        )

        render json: {
          keystore_password: @keystore.keystore_password,
          key_password:      @keystore.key_password,
          key_alias:         @keystore.key_alias
        }
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_keystore
        @keystore = @organization.android_keystores.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Keystore")
      end
    end
  end
end
