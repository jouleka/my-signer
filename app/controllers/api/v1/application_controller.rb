module Api
  module V1
    class ApplicationController < ActionController::API
      # ActionController::API does NOT include forgery protection by default.
      # We pull it in so session-cookie-authenticated callers (the web UI
      # calling these JSON endpoints) are still CSRF-protected on
      # state-changing actions. Token-authenticated callers (CLI/Postman with
      # a Bearer token) are exempt — they don't ride on the session cookie and
      # an attacker's site can't read/forge the Authorization header.
      include ActionController::RequestForgeryProtection
      include Pundit::Authorization
      include ApiErrorHandler
      include AutoSync
      include SanitizesErrorMessage

      # We deliberately do NOT call `protect_from_forgery` here: that would
      # register an UNconditional `verify_authenticity_token` before_action and
      # break legitimate Bearer-token requests (which have no CSRF token). We
      # instead set the strategy and invoke the check ourselves below, scoped to
      # session-authenticated callers only. `:exception` => an unverified
      # session request raises InvalidAuthenticityToken (rescued -> 403) rather
      # than silently nulling the session.
      self.forgery_protection_strategy =
        ActionController::RequestForgeryProtection::ProtectionMethods::Exception

      before_action :authenticate_api_user!
      before_action :verify_authenticity_token_for_session_auth!

      rescue_from ActionController::InvalidAuthenticityToken do
        render json: {
          error:     "invalid_csrf_token",
          message:   "CSRF token verification failed",
          timestamp: Time.current.iso8601
        }, status: :forbidden
      end

      private

      # CSRF is only meaningful for cookie/session-authenticated requests: the
      # browser auto-attaches the session cookie, so a cross-site form could
      # otherwise drive a state-changing action. Bearer-token requests carry no
      # ambient credential and are exempt. GET/HEAD are assumed side-effect-free
      # (Rails' own forgery_protection convention) and are skipped.
      def verify_authenticity_token_for_session_auth!
        return if @current_user.nil?            # auth already failed -> 401 rendered
        return if @current_api_token.present?   # token auth: no session cookie involved
        return if request.get? || request.head?

        verify_authenticity_token
      end

      def authenticate_api_user!
        # Try token auth first, fallback to session auth (for Postman, web requests)
        @current_user = authenticate_with_token || authenticate_with_session

        if @current_user.nil?
          # Use custom error message if set (e.g., email validation failure)
          error_response = @auth_error || { error: "unauthorized", message: "Invalid or missing API token" }
          render json: error_response, status: :unauthorized
        end
      end

      def authenticate_with_token
        # Extract token from Authorization header: "Bearer TOKEN"
        auth_header = request.headers["Authorization"]
        return nil if auth_header.blank?

        token = auth_header.match(/^Bearer (.+)$/)&.captures&.first
        return nil if token.blank?

        api_token = ApiToken.find_by_token(token)
        if api_token&.active?
          # Email match check: only runs IF the header is provided. Credential
          # controllers separately REQUIRE the header via `require_user_email!`
          # (mysigner-30). Don't remove that per-controller before_action
          # thinking this layer enforces presence — it does not.
          provided_email = request.headers["X-User-Email"]

          # If email is provided, validate it matches the token's user
          if provided_email.present?
            # Normalize emails for comparison (case-insensitive, strip whitespace)
            token_email = api_token.user.email.to_s.strip.downcase
            provided_email = provided_email.to_s.strip.downcase

            if token_email != provided_email
              # Set error flag for authenticate_api_user! to render
              @auth_error = {
                error: "unauthorized",
                message: "This token doesn't belong to #{request.headers["X-User-Email"]}. Please use your own token.",
                timestamp: Time.current.iso8601
              }
              return nil
            end
          end

          api_token.touch_last_used!
          @current_api_token = api_token
          @token_organization_id = api_token.organization_id
          api_token.user
        else
          nil
        end
      end

      def authenticate_with_session
        # Fallback to Devise session (for web-based API calls)
        request.env["warden"]&.user
      end

      def current_user
        @current_user
      end

      def current_api_token
        @current_api_token
      end

      def current_organization
        # If using token auth, return the token's organization.
        return @current_api_token.organization if @current_api_token

        # Otherwise (session auth) fall back to the params org — but ONLY among
        # organizations the authenticated user actually belongs to. Without this
        # scope a caller could name ANY org id and have it returned here; even
        # though actions authorize afterwards, an unscoped fallback is a
        # foot-gun (e.g. anything reading current_organization before authorize).
        return nil if @current_user.nil? || params[:organization_id].blank?

        @current_user.organizations.find_by(id: params[:organization_id])
      end

      def token_organization_id
        @token_organization_id
      end

      # Require the X-User-Email header on credential endpoints when the
      # caller is using token auth. A leaked API token alone should NOT be
      # sufficient to read or write credential material — the legitimate
      # caller (CLI) always sends the header; a thief generally does not
      # know which email the token belongs to.
      #
      # Session-authenticated callers (web UI) are exempt: they're already
      # identity-bound by Devise's session, and the header is optional in
      # that flow per the original authenticate_with_token contract.
      #
      # Used by credential controllers as a `before_action`. Renders 401
      # and halts the chain when missing.
      def require_user_email!
        return unless @current_api_token.present?
        return if request.headers["X-User-Email"].present?

        render json: {
          error:     "unauthorized",
          message:   "X-User-Email header is required for credential endpoints",
          timestamp: Time.current.iso8601
        }, status: :unauthorized
      end

      def verify_token_organization_access!
        # Only enforce if using token auth (not session auth)
        return unless @current_api_token.present?

        # For nested routes like /organizations/:organization_id/profiles/:id
        # use organization_id. For top-level routes like /organizations/:id,
        # use id (which refers to the organization).
        requested_org_id = if params[:organization_id].present?
                             params[:organization_id].to_i
        elsif params[:id].present? && controller_name == "organizations"
                             params[:id].to_i
        else
                             return # No org ID to check
        end

        if @token_organization_id != requested_org_id
          render_forbidden_error("This API token belongs to a different organization and cannot access the requested organization")
        end
      end

      # Centralized scope verification methods
      def verify_read_scope!
        return unless current_api_token
        return if current_api_token.has_scope?("read") || current_api_token.has_scope?("admin")

        render_insufficient_scope("read")
      end

      def verify_write_scope!
        return unless current_api_token
        return if current_api_token.has_scope?("write") || current_api_token.has_scope?("admin")

        render_insufficient_scope("write")
      end

      def verify_admin_scope!
        return unless current_api_token
        return if current_api_token.has_scope?("admin")

        render_insufficient_scope("admin")
      end

      def organization_plan_payload(organization)
        Pricing::PlanPayload.for_organization(organization)
      end

      def plan_upgrade_suggestion(current_plan:, required_plan:, feature:)
        current_name = current_plan.to_s.titleize
        required_name = required_plan.to_s.titleize

        if current_plan.to_s == required_plan.to_s
          "Your #{current_name} plan has reached its limit for #{feature}. Reduce usage or move to a higher plan."
        else
          "Upgrade from #{current_name} to #{required_name} to use #{feature}."
        end
      end

      def quota_upgrade_suggestion(current_plan:, next_plan:, feature:)
        current_name = current_plan.to_s.titleize

        if next_plan.present? && next_plan.to_s != current_plan.to_s
          "Upgrade from #{current_name} to #{next_plan.to_s.titleize} to increase the #{feature} limit."
        else
          "Your #{current_name} plan has reached its #{feature} limit. Wait for the limit window to reset or reduce usage."
        end
      end
    end
  end
end
