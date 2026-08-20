module Api
  module V1
    class DevicesController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_device, only: [ :show, :update ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_or_admin_scope, only: [ :create, :update ]

      # GET /api/v1/organizations/:organization_id/devices
      # Returns all devices for the organization with optional filters
      def index
        authorize @organization, :show?

        scope = @organization.apple_devices

        # Apply filters
        scope = scope.where(platform: params[:platform]) if params[:platform].present?
        scope = scope.where(status: params[:status]) if params[:status].present?

        # Apply search query
        if params[:q].present?
          query = params[:q].strip
          scope = scope.where("name ILIKE :q OR udid ILIKE :q", q: "%#{query}%")
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min # max 100 per page
        per_page = 50 if per_page == 1 && params[:per_page].blank? # default 50

        total = scope.count
        devices = scope.order(created_at: :desc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          devices: devices.map { |device| device_json(device) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/devices/:id
      # Returns detailed information about a specific device
      def show
        authorize @organization, :show?

        render json: device_json(@device)
      end

      # POST /api/v1/organizations/:organization_id/devices
      # Register a new device with App Store Connect
      def create
        authorize @organization, :sync?

        # Validate required params
        unless params[:name].present? && params[:udid].present? && params[:platform].present?
          return render_invalid_request("Missing required parameters: name, udid, platform")
        end

        # Get active App Store Connect credential
        credential = @organization.app_store_connect_credentials.where(active: true).first
        unless credential
          return render_credentials_required("No active App Store Connect credential found")
        end

        # Check if device already exists
        existing_device = @organization.apple_devices.find_by(udid: params[:udid])
        if existing_device
          return render_conflict(
            "Device with UDID #{params[:udid]} already exists",
            resource_id: existing_device.id,
            details: { device: device_json(existing_device) }
          )
        end

        # Register device with App Store Connect
        begin
          client = AppStoreConnect::Client.new(credential: credential)
          service = AppStoreConnect::Devices.new(client)
          response = service.register(
            name: params[:name],
            platform: params[:platform],
            udid: params[:udid]
          )

          # Create device record
          attributes = response.dig("data", "attributes") || {}
          device = @organization.apple_devices.create!(
            remote_id: response.dig("data", "id"),
            name: attributes["name"] || params[:name],
            udid: attributes["udid"] || params[:udid],
            platform: attributes["platform"] || params[:platform],
            device_class: attributes["deviceClass"],
            status: attributes["status"],
            added_at: attributes["addedDate"],
            raw_json: JSON.dump(response)
          )

          render json: {
            message: "Device registered successfully",
            device: device_json(device)
          }, status: :created
        rescue => e
          Rails.logger.error("Device registration failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Device registration failed: #{sanitize_error_message(e)}")
        end
      end

      # PATCH /api/v1/organizations/:organization_id/devices/:id
      # Update device name (note: only name can be updated in Apple's API)
      def update
        authorize @organization, :sync?

        unless params[:name].present?
          return render_invalid_request("Missing required parameter: name")
        end

        # Update locally only (Apple API doesn't support device updates easily)
        # For production, you'd call Apple API and sync back
        if @device.update(name: params[:name])
          render json: {
            message: "Device updated successfully",
            device: device_json(@device)
          }
        else
          render_operation_failed("Device update failed: #{@device.errors.full_messages.join(', ')}")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_device
        @device = @organization.apple_devices.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Device")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      def device_json(device)
        {
          id: device.id,
          remote_id: device.remote_id,
          name: device.name,
          udid: device.udid,
          platform: device.platform,
          device_class: device.device_class,
          status: device.status,
          added_at: device.added_at&.iso8601,
          created_at: device.created_at.iso8601,
          updated_at: device.updated_at.iso8601
        }
      end
    end
  end
end
