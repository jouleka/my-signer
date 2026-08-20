module Api
  module V1
    class CertificatesController < ApplicationController
      before_action :set_organization
      before_action :verify_token_organization_access!
      before_action :set_certificate, only: [ :show, :download ]
      before_action :verify_read_scope

      # GET /api/v1/organizations/:organization_id/certificates
      # Returns all certificates for the organization with optional filters
      def index
        authorize @organization, :show?

        scope = @organization.apple_certificates

        # Apply filters
        scope = scope.where(certificate_type: params[:certificate_type]) if params[:certificate_type].present?
        scope = scope.where(platform: params[:platform]) if params[:platform].present?
        scope = scope.where(status: params[:status]) if params[:status].present?

        # Apply search query
        if params[:q].present?
          query = params[:q].strip
          scope = scope.where("name ILIKE :q OR serial_number ILIKE :q", q: "%#{query}%")
        end

        # Pagination
        page = [ params[:page].to_i, 1 ].max
        per_page = [ [ params[:per_page].to_i, 1 ].max, 100 ].min
        per_page = 50 if per_page == 1 && params[:per_page].blank?

        total = scope.count
        certificates = scope.order(expires_at: :asc, name: :asc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          certificates: certificates.map { |cert| certificate_json(cert) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # GET /api/v1/organizations/:organization_id/certificates/:id
      # Returns detailed information about a specific certificate
      def show
        authorize @organization, :show?

        render json: certificate_json(@certificate)
      end

      # GET /api/v1/organizations/:organization_id/certificates/:id/download
      # Download the certificate as .cer file
      def download
        authorize @organization, :show?

        # raw_json is a jsonb column, already a hash
        raw = @certificate.raw_json

        content = nil
        if raw.is_a?(Hash)
          content = raw.dig("attributes", "certificateContent") || raw.dig("data", "attributes", "certificateContent")
        end

        unless content.present?
          return render_not_found("Certificate content", details: {
            suggestion: "Try syncing the organization first"
          })
        end

        # Decode base64 content
        data = begin
          Base64.strict_decode64(content)
        rescue ArgumentError
          Base64.decode64(content)
        end

        # Determine file extension (cer for most, p12 for some)
        extension = "cer"
        filename = "#{@certificate.name || @certificate.serial_number}.#{extension}"

        send_data(data,
                  filename: filename,
                  type: "application/x-x509-ca-cert",
                  disposition: "attachment")
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Organization")
      end

      def set_certificate
        @certificate = @organization.apple_certificates.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Certificate")
      end

      def verify_read_scope
        verify_read_scope!
      end

      def certificate_json(cert)
        {
          id: cert.id,
          remote_id: cert.remote_id,
          name: cert.name,
          certificate_type: cert.certificate_type,
          serial_number: cert.serial_number,
          platform: cert.platform,
          status: cert.status,
          expires_at: cert.expires_at&.iso8601,
          created_at: cert.created_at.iso8601,
          updated_at: cert.updated_at.iso8601
        }
      end
    end
  end
end
