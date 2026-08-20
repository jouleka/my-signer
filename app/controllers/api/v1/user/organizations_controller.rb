module Api
  module V1
    module User
      class OrganizationsController < Api::V1::ApplicationController
        before_action :verify_read_scope

        # GET /api/v1/user/organizations
        # Returns all organizations the current user is a member of
        # This endpoint is NOT restricted by the token's organization
        # It's specifically for the CLI to discover all user organizations
        def index
          @organizations = policy_scope(Organization)

          render json: {
            organizations: @organizations.map { |org| organization_discovery_payload(org) },
            total: @organizations.count
          }
        end

        private

        def verify_read_scope
          verify_read_scope!
        end

        def membership_role(org)
          return nil unless current_user

          return "owner" if org.owner_id == current_user.id

          membership = org.memberships.find_by(user_id: current_user.id)
          membership&.role
        end

        def organization_discovery_payload(org)
          payload = {
            id: org.id,
            name: org.name,
            role: membership_role(org),
            plan: organization_plan_payload(org)
          }

          unless current_api_token.present?
            payload[:member_count] = org.memberships.count
          end

          payload
        end
      end
    end
  end
end
