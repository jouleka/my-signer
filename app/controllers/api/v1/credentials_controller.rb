module Api
  module V1
    # mysigner-47: server-side credential retention. The `DELETE
    # /credentials` action implements the bulk purge that `mysigner
    # logout --purge` (and the default-No prompt on `mysigner logout`)
    # calls when the user opts to wipe stored signing material.
    #
    # Scope of purge: every AppStoreConnectCredential, AppleAdsCredential,
    # GooglePlayCredential and AndroidKeystore owned by the current org.
    # The endpoint is org-scoped (the API token is org-scoped and the
    # `manage_credentials?` Pundit policy is per-org); cross-org cascading
    # is intentionally out of scope.
    #
    # Hard delete: per the retention policy (see
    # docs/policy/credential-retention.md), logout is user-initiated
    # deletion. Rows are destroyed; AuditEvent rows survive (their
    # belongs_to :resource is optional).
    #
    # Each destroyed row emits a `credential_destroyed_on_logout` audit
    # event BEFORE the destroy call so `resource_id` is captured.
    class CredentialsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :require_user_email!
      before_action :verify_write_or_admin_scope, only: [ :destroy ]

      # DELETE /api/v1/organizations/:organization_id/credentials
      def destroy
        authorize @organization, :manage_credentials?

        counts = { asc: 0, apple_ads: 0, google_play: 0, android_keystore: 0 }

        counts[:asc]              = purge_collection(@organization.app_store_connect_credentials, kind: "asc")
        counts[:apple_ads]        = purge_one(@organization.apple_ads_credential, kind: "apple_ads")
        counts[:google_play]      = purge_collection(@organization.google_play_credentials, kind: "google_play")
        counts[:android_keystore] = purge_collection(@organization.android_keystores, kind: "android_keystore")

        render json: { deleted: counts }, status: :ok
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      # `has_many` collection — iterate, audit, destroy. Returns count.
      def purge_collection(relation, kind:)
        count = 0
        relation.find_each do |record|
          audit_destroyed!(record, kind: kind)
          record.destroy
          count += 1
        end
        count
      end

      # `has_one` association — single optional record. Returns 0 or 1.
      def purge_one(record, kind:)
        return 0 unless record
        audit_destroyed!(record, kind: kind)
        record.destroy
        1
      end

      # Emit BEFORE destroy: `resource_id` references the row id, which is
      # gone afterward. Audit::Logger.log itself rescues internally so a
      # failed audit write will not block the destroy.
      def audit_destroyed!(record, kind:)
        Audit::Logger.log(
          organization: @organization,
          actor:        current_user,
          action:       "credential_destroyed_on_logout",
          resource:     record,
          request:      request,
          metadata: {
            kind:            kind,
            credential_id:   record.id,
            organization_id: @organization.id
          }
        )
      end
    end
  end
end
