module Api
  module V1
    class ProfilesController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_profile, only: [ :show, :download, :destroy ]
      before_action :verify_read_scope, only: [ :index, :show, :download, :match ]
      before_action :verify_write_or_admin_scope, only: [ :create, :destroy, :auto_create ]

      # GET /api/v1/organizations/:organization_id/profiles
      # Returns all provisioning profiles for the organization with optional filters
      def index
        authorize @organization, :show?

        scope = @organization.apple_provisioning_profiles

        # Apply filters
        scope = scope.where(profile_type: params[:type]) if params[:type].present?
        scope = scope.where(state: params[:state]) if params[:state].present?
        scope = scope.where(bundle_id_identifier: params[:bundle_id]) if params[:bundle_id].present?

        # Apply search query
        if params[:q].present?
          query = params[:q].strip
          scope = scope.where("name ILIKE :q OR uuid ILIKE :q", q: "%#{query}%")
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min
        per_page = 50 if per_page == 1 && params[:per_page].blank?

        total = scope.count
        profiles = scope.order(expires_at: :asc, name: :asc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          profiles: profiles.map { |profile| profile_json(profile) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/profiles/:id
      # Returns detailed information about a specific profile
      def show
        authorize @organization, :show?

        render json: profile_json(@profile)
      end

      # GET /api/v1/organizations/:organization_id/profiles/match
      # Find the best matching profile for a bundle ID and type
      def match
        authorize @organization, :show?

        # Validate required params
        unless params[:bundle_id].present? && params[:type].present?
          return render_invalid_request("Missing required parameters: bundle_id, type")
        end

        bundle_identifier = params[:bundle_id]
        profile_type = map_profile_type(params[:type])

        # Find matching profiles
        scope = @organization.apple_provisioning_profiles
                            .where(bundle_id_identifier: bundle_identifier)
                            .where(profile_type: profile_type)
                            .where(state: "ACTIVE")
                            .where("expires_at > ?", Time.current)
                            .order(expires_at: :desc)

        profile = scope.first

        if profile
          render json: {
            profile: profile_json(profile),
            message: "Found matching profile"
          }
        else
          # Provide helpful error message
          any_profiles = @organization.apple_provisioning_profiles
                                     .where(bundle_id_identifier: bundle_identifier)
                                     .exists?

          if any_profiles
            render_not_found("Profile", details: {
              bundle_id: bundle_identifier,
              type: profile_type,
              reason: "No active, non-expired profile found",
              suggestion: "Create a new profile or check existing profiles are not expired"
            })
          else
            render_not_found("Profile", details: {
              bundle_id: bundle_identifier,
              reason: "No profiles found for this bundle ID",
              suggestion: "Create a profile for this bundle ID first"
            })
          end
        end
      end

      # POST /api/v1/organizations/:organization_id/profiles
      # Create a new provisioning profile
      def create
        authorize @organization, :sync?

        # Validate required params
        unless params[:name].present? && params[:profile_type].present? && params[:bundle_id_id].present?
          return render_invalid_request("Missing required parameters: name, profile_type, bundle_id_id")
        end

        # Validate certificate_ids
        cert_ids = Array(params[:certificate_ids]).reject(&:blank?)
        if cert_ids.empty?
          return render_invalid_request("At least one certificate is required")
        end

        # Get active App Store Connect credential
        credential = @organization.app_store_connect_credentials.where(active: true).first
        unless credential
          return render_credentials_required("No active App Store Connect credential found")
        end

        begin
          client = AppStoreConnect::Client.new(credential: credential)
          service = AppStoreConnect::Profiles.new(client)
          response = service.create(
            name: params[:name],
            profile_type: params[:profile_type],
            bundle_id_id: params[:bundle_id_id],
            certificate_ids: cert_ids,
            device_ids: Array(params[:device_ids]).reject(&:blank?)
          )

          # Create profile record
          attributes = response.dig("data", "attributes") || {}
          profile = @organization.apple_provisioning_profiles.create!(
            remote_id: response.dig("data", "id"),
            name: attributes["name"] || params[:name],
            uuid: attributes["uuid"],
            profile_type: attributes["profileType"] || params[:profile_type],
            state: attributes["profileState"],
            platform: attributes["platform"],
            bundle_id_identifier: params[:bundle_id_id],
            expires_at: (attributes["expirationDate"] rescue nil),
            raw_json: JSON.dump(response)
          )

          # Trigger async sync to refresh
          AppStoreConnectSyncJob.perform_later(@organization.id)

          render json: {
            message: "Profile created successfully. Sync triggered to refresh data.",
            profile: profile_json(profile)
          }, status: :created
        rescue => e
          Rails.logger.error("Profile creation failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Profile creation failed: #{sanitize_error_message(e)}")
        end
      end

      # POST /api/v1/organizations/:organization_id/profiles/auto_create
      # Auto-create a provisioning profile with smart defaults
      def auto_create
        authorize @organization, :sync?

        # Validate required params
        unless params[:bundle_id].present? && params[:profile_type].present?
          return render_invalid_request("Missing required parameters: bundle_id, profile_type")
        end

        bundle_identifier = params[:bundle_id]
        profile_type = map_profile_type(params[:profile_type])

        # Get active App Store Connect credential
        credential = @organization.app_store_connect_credentials.where(active: true).first
        unless credential
          return render_credentials_required("No active App Store Connect credential found")
        end

        # Find bundle ID in our database
        bundle_id_record = @organization.apple_bundle_ids.find_by(identifier: bundle_identifier)
        unless bundle_id_record
          return render_not_found("Bundle ID", details: {
            identifier: bundle_identifier,
            suggestion: "Run sync or register the bundle ID in App Store Connect"
          })
        end

        # Select appropriate certificates
        cert_type = certificate_type_for_profile(profile_type)
        certificates = @organization.apple_certificates
                                   .where(certificate_type: cert_type)
                                   .where("expires_at > ?", Time.current)
                                   .order(expires_at: :desc)

        if certificates.empty?
          return render_precondition_failed(
            "No valid #{cert_type} certificates found",
            suggestion: "Create or sync certificates first"
          )
        end

        # Select devices for development/adhoc profiles
        device_ids = []
        if profile_type.in?([ "IOS_APP_DEVELOPMENT", "IOS_APP_ADHOC" ])
          devices = @organization.apple_devices
                                .where(status: "ENABLED")
                                .where(platform: [ "IOS", nil ])
                                .order(name: :asc)

          if devices.empty?
            return render_precondition_failed(
              "No enabled devices found for #{profile_type} profile",
              suggestion: "Add devices first"
            )
          end

          device_ids = devices.pluck(:remote_id)
        end

        # Generate profile name
        type_suffix = case profile_type
        when "IOS_APP_DEVELOPMENT" then "Development"
        when "IOS_APP_STORE" then "App Store"
        when "IOS_APP_ADHOC" then "Ad Hoc"
        when "IOS_APP_INHOUSE" then "In House"
        else profile_type
        end
        profile_name = "#{bundle_identifier} #{type_suffix}"

        begin
          client = AppStoreConnect::Client.new(credential: credential)
          service = AppStoreConnect::Profiles.new(client)
          response = service.create(
            name: profile_name,
            profile_type: profile_type,
            bundle_id_id: bundle_id_record.remote_id,
            certificate_ids: certificates.pluck(:remote_id),
            device_ids: device_ids
          )

          # Create profile record
          attributes = response.dig("data", "attributes") || {}
          profile = @organization.apple_provisioning_profiles.create!(
            remote_id: response.dig("data", "id"),
            name: attributes["name"] || profile_name,
            uuid: attributes["uuid"],
            profile_type: attributes["profileType"] || profile_type,
            state: attributes["profileState"],
            platform: attributes["platform"],
            bundle_id_identifier: bundle_identifier,
            expires_at: (attributes["expirationDate"] rescue nil),
            raw_json: JSON.dump(response)
          )

          render json: {
            message: "Profile created successfully",
            profile: profile_json(profile),
            details: {
              certificates_used: certificates.count,
              devices_used: device_ids.count
            }
          }, status: :created
        rescue => e
          Rails.logger.error("Profile creation failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Profile creation failed: #{sanitize_error_message(e)}")
        end
      end

      # GET /api/v1/organizations/:organization_id/profiles/:id/download
      # Download the .mobileprovision file
      def download
        authorize @organization, :show?

        # First try to get content from stored raw_json
        content = nil
        raw = begin
          JSON.parse(@profile.raw_json)
        rescue JSON::ParserError, TypeError
          nil
        end

        if raw.is_a?(Hash)
          content = raw.dig("attributes", "profileContent") || raw.dig("data", "attributes", "profileContent")
        end

        # If not in database, fetch directly from Apple's API
        unless content.present?
          credential = @organization.app_store_connect_credentials.active.first
          unless credential
            return render_credentials_required("No active App Store Connect credential found")
          end

          begin
            client = AppStoreConnect::Client.new(credential: credential)
            # Fetch profile with profileContent field
            response = client.get("profiles/#{@profile.remote_id}", params: { "fields[profiles]" => "profileContent,name,uuid" })
            content = response.dig("data", "attributes", "profileContent")
          rescue => e
            Rails.logger.error("Failed to fetch profile content from Apple: #{e.message}")
          end
        end

        unless content.present?
          return render_not_found("Profile content", details: {
            reason: "Profile content not available from Apple. The profile may have been deleted or is invalid."
          })
        end

        # Decode base64 content
        data = begin
          Base64.strict_decode64(content)
        rescue ArgumentError
          Base64.decode64(content)
        end

        send_data(data,
                  filename: "#{@profile.name}.mobileprovision",
                  type: "application/octet-stream",
                  disposition: "attachment")
      end

      # DELETE /api/v1/organizations/:organization_id/profiles/:id
      # Delete a provisioning profile from App Store Connect
      def destroy
        authorize @organization, :sync?

        # Get active App Store Connect credential
        credential = @organization.app_store_connect_credentials.where(active: true).first
        unless credential
          return render_credentials_required("No active App Store Connect credential found")
        end

        begin
          client = AppStoreConnect::Client.new(credential: credential)
          service = AppStoreConnect::Profiles.new(client)

          # Delete from Apple
          service.delete(@profile.remote_id)

          # Delete from database
          @profile.destroy

          render json: {
            message: "Profile deleted successfully"
          }, status: :ok
        rescue => e
          Rails.logger.error("Profile deletion failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Profile deletion failed: #{sanitize_error_message(e)}")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_profile
        @profile = @organization.apple_provisioning_profiles.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Profile")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      def profile_json(profile)
        {
          id: profile.id,
          remote_id: profile.remote_id,
          name: profile.name,
          uuid: profile.uuid,
          profile_type: profile.profile_type,
          state: profile.state,
          platform: profile.platform,
          bundle_id_identifier: profile.bundle_id_identifier,
          expires_at: profile.expires_at&.iso8601,
          created_at: profile.created_at.iso8601,
          updated_at: profile.updated_at.iso8601
        }
      end

      def map_profile_type(type)
        case type.to_s.downcase
        when "development", "dev"
          "IOS_APP_DEVELOPMENT"
        when "appstore", "store", "app-store"
          "IOS_APP_STORE"
        when "adhoc", "ad-hoc"
          "IOS_APP_ADHOC"
        when "inhouse", "in-house", "enterprise"
          "IOS_APP_INHOUSE"
        else
          # Try uppercase version as-is
          type.to_s.upcase
        end
      end

      def certificate_type_for_profile(profile_type)
        case profile_type
        when "IOS_APP_DEVELOPMENT"
          [ "DEVELOPMENT", "IOS_DEVELOPMENT", "IOS_APP_DEVELOPMENT" ]
        when "IOS_APP_STORE", "IOS_APP_ADHOC", "IOS_APP_INHOUSE"
          [ "DISTRIBUTION", "IOS_DISTRIBUTION", "IOS_APP_DISTRIBUTION" ]
        else
          [ "DEVELOPMENT", "IOS_DEVELOPMENT", "IOS_APP_DEVELOPMENT" ]
        end
      end
    end
  end
end
