module Api
  module V1
    class MerchantIdsController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_merchant_id, only: [ :show, :destroy ]
      before_action :verify_read_scope, only: [ :index, :show ]
      before_action :verify_write_or_admin_scope, only: [ :create, :destroy ]

      # GET /api/v1/organizations/:organization_id/merchant_ids
      # Returns all merchant IDs for the organization
      def index
        authorize @organization, :show?

        scope = @organization.apple_merchant_ids

        # Apply search query
        if params[:q].present?
          query = params[:q].strip
          scope = scope.where("identifier ILIKE :q OR name ILIKE :q", q: "%#{query}%")
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min
        per_page = 50 if per_page == 1 && params[:per_page].blank?

        total = scope.count
        merchant_ids = scope.sorted.offset((page - 1) * per_page).limit(per_page)

        render json: {
          merchant_ids: merchant_ids.map { |m| merchant_id_json(m) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/merchant_ids/:id
      # Returns detailed information about a specific merchant ID
      def show
        authorize @organization, :show?

        render json: merchant_id_json(@merchant_id, include_bundle_ids: true)
      end

      # POST /api/v1/organizations/:organization_id/merchant_ids
      # Register a merchant ID locally (must be created in Apple Developer Portal first)
      # Note: Apple has no public API for merchantIds, so this only registers locally
      def create
        authorize @organization, :sync?

        unless params[:identifier].present?
          return render_invalid_request("Missing required parameter: identifier")
        end

        unless params[:identifier].start_with?("merchant.")
          return render_invalid_request("Identifier must start with 'merchant.'")
        end

        # Check if merchant ID already exists
        existing = @organization.apple_merchant_ids.find_by(identifier: params[:identifier])
        if existing
          return render_conflict(
            "Merchant ID with identifier #{params[:identifier]} already exists",
            resource_id: existing.id,
            details: { merchant_id: merchant_id_json(existing) }
          )
        end

        # Get team_id from credential if available
        credential = @organization.app_store_connect_credentials.where(active: true).first

        begin
          # Create locally only - Apple has no public API for merchantIds
          merchant_id = @organization.apple_merchant_ids.create!(
            remote_id: "local_#{SecureRandom.hex(8)}",
            identifier: params[:identifier],
            name: params[:name].presence || params[:identifier],
            team_id: credential&.team_id
          )

          render json: {
            message: "Merchant ID registered locally. Remember to also create it in the Apple Developer Portal.",
            merchant_id: merchant_id_json(merchant_id)
          }, status: :created
        rescue => e
          Rails.logger.error("Merchant ID creation failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Merchant ID creation failed: #{sanitize_error_message(e)}")
        end
      end

      # DELETE /api/v1/organizations/:organization_id/merchant_ids/:id
      # Remove a merchant ID from local tracking (must be deleted from Apple Developer Portal separately)
      def destroy
        authorize @organization, :sync?

        begin
          @merchant_id.destroy!

          render json: {
            message: "Merchant ID removed from My Signer. If needed, delete it from Apple Developer Portal as well."
          }
        rescue => e
          Rails.logger.error("Merchant ID deletion failed: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          render_operation_failed("Merchant ID deletion failed: #{sanitize_error_message(e)}")
        end
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_merchant_id
        @merchant_id = @organization.apple_merchant_ids.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Merchant ID")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def verify_write_or_admin_scope
        verify_write_scope!
      end

      def merchant_id_json(merchant_id, include_bundle_ids: false)
        json = {
          id: merchant_id.id,
          remote_id: merchant_id.remote_id,
          identifier: merchant_id.identifier,
          name: merchant_id.name,
          team_id: merchant_id.team_id,
          created_at: merchant_id.created_at.iso8601,
          updated_at: merchant_id.updated_at.iso8601
        }

        if include_bundle_ids
          json[:bundle_ids] = merchant_id.apple_bundle_ids.map do |b|
            {
              id: b.id,
              identifier: b.identifier,
              name: b.name
            }
          end
        end

        json
      end
    end
  end
end
