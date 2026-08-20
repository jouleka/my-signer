module Api
  module V1
    class AndroidKeystoresController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :require_user_email!
      before_action :set_keystore, only: [ :destroy, :download, :activate, :link_to_app ]
      before_action :verify_read_scope, only: [ :index ]
      # A .jks file contains the private signing key, so the download action
      # is at least as sensitive as returning keystore_password from the
      # secrets endpoint. Both require admin scope for the same reason: a
      # compromised write-only token must not be able to exfiltrate signing
      # material the removed GET /credentials endpoint guarded with admin.
      before_action :verify_admin_scope, only: [ :download ]
      before_action :verify_write_scope, only: [ :create, :destroy, :activate, :link_to_app ]

      # GET /api/v1/organizations/:organization_id/android_keystores
      # Optional: android_app_id param (filter by app association)
      def index
        authorize @organization, :show?

        # Phase 0 hard removal: ?include_secrets=true is GONE. Old CLIs that
        # send it get a structured 410 forcing an upgrade — silently ignoring
        # would have returned an empty-password list and produced corrupted
        # wrongly-signed builds without any error.
        if ActiveModel::Type::Boolean.new.cast(params[:include_secrets])
          return render json: {
            error:       "parameter_removed",
            message:     "include_secrets is no longer supported. Upgrade my-signer-cli to >= 0.2.0.",
            upgrade_url: "https://mysigner.dev/docs/cli/upgrade"
          }, status: :gone
        end

        scope = @organization.android_keystores
        # If filtering by app, include both app-specific AND org-wide keystores
        if params[:android_app_id].present?
          scope = scope.where(android_app_id: [ params[:android_app_id], nil ])
        end

        # Order: active first, app-specific before org-wide, then by created_at
        ordered = scope.order(
          Arel.sql("active DESC, CASE WHEN android_app_id IS NOT NULL THEN 0 ELSE 1 END, created_at DESC")
        )
        render json: {
          android_keystores: ordered.map { |k| keystore_json(k) }
        }
      end

      # POST /api/v1/organizations/:organization_id/android_keystores
      # Body: { android_keystore: { name:, keystore_file_base64:, keystore_password:, key_alias:, key_password:, android_app_id: (optional), active: true/false } }
      def create
        authorize @organization, :manage_credentials?

        attrs = keystore_params
        keystore = @organization.android_keystores.new
        keystore.name = attrs[:name]
        keystore.android_app_id = attrs[:android_app_id]
        keystore.keystore_password = attrs[:keystore_password]
        keystore.key_alias = attrs[:key_alias]
        keystore.key_password = attrs[:key_password]
        requested_active = ActiveModel::Type::Boolean.new.cast(attrs[:active])

        # Decode base64 keystore content
        b64 = attrs[:keystore_file_base64].to_s
        if b64.blank?
          return render_invalid_request("keystore_file_base64 is required")
        end

        begin
          raw = Base64.strict_decode64(b64)
        rescue
          raw = Base64.decode64(b64)
        end
        if raw.blank?
          return render_invalid_request("Invalid keystore_file_base64")
        end
        keystore.keystore_file = raw

        # To avoid unique constraint on active keystores, persist as inactive first if activation was requested
        keystore.active = false if requested_active

        if keystore.save
          keystore.activate_exclusively! if requested_active

          Audit::Logger.log(
            organization: @organization,
            actor:        current_user,
            action:       "android_keystore_added",
            resource:     keystore,
            request:      request,
            metadata: {
              credential_id:      keystore.id,
              name:               keystore.name,
              android_app_id:     keystore.android_app_id,
              key_alias:          keystore.key_alias,
              fingerprint_sha256: keystore.fingerprint_sha256,
              active:             keystore.active
            }
          )

          render json: keystore_json(keystore), status: :created
        else
          render_validation_failed("Failed to create keystore", details: keystore.errors.full_messages)
        end
      end

      # DELETE /api/v1/organizations/:organization_id/android_keystores/:id
      def destroy
        authorize @organization, :manage_credentials?
        @keystore.destroy
        render json: { message: "Keystore deleted" }, status: :ok
      end

      # GET /api/v1/organizations/:organization_id/android_keystores/:id/download
      def download
        authorize @organization, :manage_credentials?

        data = @keystore.keystore_file
        if data.blank?
          return render_not_found("Keystore file")
        end

        Audit::Logger.log(
          organization: @organization,
          actor: current_user,
          action: "credential_read_android_keystore_file",
          metadata: {
            credential_id:   @keystore.id,
            credential_name: @keystore.name,
            outcome:         "ok"
          }
        )

        send_data(data, filename: download_filename(@keystore), type: "application/octet-stream", disposition: "attachment")
      end

      # POST /api/v1/organizations/:organization_id/android_keystores/:id/activate
      def activate
        authorize @organization, :manage_credentials?
        @keystore.activate_exclusively!
        render json: keystore_json(@keystore), status: :ok
      end

      # POST /api/v1/organizations/:organization_id/android_keystores/:id/link_to_app
      # Body: { package_name: "com.example.app" }
      # Links this keystore to an Android app. If already linked to a different app,
      # makes it org-wide (available to all apps in the org).
      def link_to_app
        authorize @organization, :manage_credentials?

        package_name = params[:package_name]
        if package_name.blank?
          return render_invalid_request("package_name is required")
        end

        app = @organization.android_apps.find_by(package_name: package_name)
        unless app
          return render_not_found("Android app", details: { package_name: package_name })
        end

        if @keystore.android_app_id.nil?
          # Not linked to any app yet → link to this app
          @keystore.update!(android_app_id: app.id, active: true)
        elsif @keystore.android_app_id == app.id
          # Already linked to this app → just ensure active
          @keystore.update!(active: true)
        else
          # Linked to a different app → make org-wide (nil) so it's available to all
          @keystore.update!(android_app_id: nil, active: true)
        end

        render json: keystore_json(@keystore), status: :ok
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

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_scope
        verify_write_scope!
      end

      def verify_admin_scope
        verify_admin_scope!
      end

      def keystore_params
        params.require(:android_keystore).permit(:name, :keystore_file_base64, :keystore_password, :key_alias, :key_password, :android_app_id, :active)
      end

      # mysigner-49: this payload never returns keystore_password / key_password.
      # Callers that need the secrets must use the dedicated, audit-logged
      # POST /android_keystores/:id/secrets endpoint (AndroidKeystoreSecretsController).
      # Keeping the helper parameter-free prevents the secrets from being
      # re-introduced here by mistake.
      def keystore_json(k)
        {
          id: k.id,
          name: k.name,
          android_app_id: k.android_app_id,
          package_name: k.android_app&.package_name,
          key_alias: k.key_alias,
          active: k.active,
          size_bytes: k.keystore_size_bytes,
          created_at: k.created_at.iso8601,
          updated_at: k.updated_at.iso8601
        }
      end

      def download_filename(k)
        base = k.name.presence || "keystore"
        pkg = k.android_app&.package_name
        suffix = pkg ? "-#{pkg}" : ""
        "#{base}#{suffix}.jks"
      end
    end
  end
end
