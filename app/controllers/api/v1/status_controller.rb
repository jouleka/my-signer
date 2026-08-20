module Api
  module V1
    class StatusController < ApplicationController
      # Simple endpoint to test API authentication
      def show
        render json: {
          status: "ok",
          message: "API authentication successful",
          user: {
            id: current_user.id,
            email: current_user.email
          },
          organization: current_api_token ? {
            id: current_api_token.organization.id,
            name: current_api_token.organization.name
          } : nil,
          token: current_api_token ? {
            name: current_api_token.name,
            scopes: current_api_token.scopes_array,
            last_used_at: current_api_token.last_used_at
          } : nil,
          timestamp: Time.current.iso8601
        }
      end
    end
  end
end
