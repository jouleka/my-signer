module Api
  module V1
    class AscBuildUploadsController < ApplicationController
      include SanitizesCredentialErrors

      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :verify_read_scope!,  only: %i[show]
      before_action :verify_write_scope!, only: %i[create update]
      before_action :set_build_upload,    only: %i[show update]

      def create
        authorize @organization, :manage_credentials?
        apple_app = @organization.apple_apps.find_by(id: params[:apple_app_id])
        return render_invalid_request("apple_app_id must belong to this organization") unless apple_app

        credential = @organization.app_store_connect_credentials.where(active: true).first
        return render_not_found("Active App Store Connect credential") unless credential

        begin
          result = AppStoreConnect::BuildUploadCreator.new(
            credential: credential,
            params: {
              apple_app: apple_app,
              cf_bundle_version:              params[:cf_bundle_version],
              cf_bundle_short_version_string: params[:cf_bundle_short_version_string],
              platform:                       params[:platform] || "IOS",
              file_name:                      params[:file_name],
              file_size:                      params[:file_size]&.to_i,
              user:                           current_user
            }
          ).call
        rescue AppStoreConnect::BuildUploadCreator::DuplicatePending => e
          return render json: { error: "duplicate_pending", message: e.message }, status: :conflict
        rescue AppStoreConnect::BuildUploadCreator::AppleError => e
          sanitized_body = sanitize_error(e.apple_body.to_s)
          return render json: {
            error: "apple_error",
            status: e.status,
            message: sanitize_error(e.message),
            apple_body: (JSON.parse(sanitized_body) rescue sanitized_body)
          }, status: :unprocessable_content
        end

        Audit::Logger.log(
          organization: @organization,
          actor: current_user,
          action: "asc_build_upload_created",
          metadata: {
            credential_id: credential.id,
            remote_id:     result[:build_upload].remote_id,
            apple_app_id:  apple_app.id,
            file_size:     result[:build_upload].file_size,
            outcome:       "ok"
          }
        )

        render json: {
          build_upload_id:             result[:build_upload].id,
          remote_build_upload_id:      result[:build_upload].remote_id,
          remote_build_upload_file_id: result[:build_upload].remote_file_id,
          upload_operations:           result[:upload_operations],
          state:                       result[:build_upload].state,
          apple_state:                 result[:build_upload].apple_state
        }, status: :created
      end

      def update
        authorize @organization, :manage_credentials?
        credential = @organization.app_store_connect_credentials.where(active: true).first
        return render_not_found("Active App Store Connect credential") unless credential

        @build_upload = AppStoreConnect::BuildUploadFinalizer.new(
          credential:   credential,
          build_upload: @build_upload,
          checksums:    (params[:source_file_checksums] || {}).to_unsafe_h.symbolize_keys
        ).call

        Audit::Logger.log(
          organization: @organization,
          actor: current_user,
          action: "asc_build_upload_finalized",
          metadata: {
            credential_id: credential.id,
            remote_id:     @build_upload.remote_id,
            outcome:       "ok"
          }
        )

        render json: payload(@build_upload)
      end

      def show
        authorize @organization, :show?
        credential = @organization.app_store_connect_credentials.where(active: true).first
        if credential
          @build_upload = AppStoreConnect::BuildUploadStatusChecker.new(credential: credential, build_upload: @build_upload).call
        end

        Audit::Logger.log(
          organization: @organization,
          actor: current_user,
          action: "asc_build_upload_status_checked",
          metadata: {
            remote_id:   @build_upload.remote_id,
            apple_state: @build_upload.apple_state,
            outcome:     "ok"
          }
        )

        render json: payload(@build_upload)
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_build_upload
        @build_upload = @organization.asc_build_uploads.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Build upload")
      end

      def payload(bu)
        {
          build_upload_id:    bu.id,
          state:              bu.state,
          apple_state:        bu.apple_state,
          apple_state_detail: bu.apple_state_detail
        }
      end
    end
  end
end
