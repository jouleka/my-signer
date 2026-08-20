module ApiErrorHandler
  extend ActiveSupport::Concern

  included do
    # Catch common exceptions and return standardized JSON errors
    rescue_from StandardError, with: :handle_internal_error if Rails.env.production?
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_invalid_record
    rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
    rescue_from Pundit::NotAuthorizedError, with: :handle_forbidden
  end

  private

  # Standardized error response format.
  #
  # Kept as a named entry point (the rescue handlers below call it) but it now
  # delegates to render_api_error, the single implementation, so the two
  # near-duplicate response builders can't drift apart.
  def render_error(error_code, message, status:, details: nil)
    render_api_error(error_code, message, status: status, details: details)
  end

  # 404 Not Found
  def handle_not_found(exception)
    render_error(
      "not_found",
      exception.message || "Resource not found",
      status: :not_found
    )
  end

  # 422 Unprocessable Entity (validation errors)
  def handle_invalid_record(exception)
    render_error(
      "validation_failed",
      "Validation failed",
      status: :unprocessable_content,
      details: exception.record.errors.messages
    )
  end

  # 422 Unprocessable Entity (missing required parameter)
  def handle_parameter_missing(exception)
    render_error(
      "parameter_missing",
      exception.message,
      status: :unprocessable_content
    )
  end

  # 403 Forbidden (authorization error)
  def handle_forbidden(exception)
    render_error(
      "forbidden",
      "You are not authorized to perform this action",
      status: :forbidden
    )
  end

  # 500 Internal Server Error
  def handle_internal_error(exception)
    # Log the error for debugging
    Rails.logger.error "Internal Server Error: #{exception.class} - #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")

    render_error(
      "internal_server_error",
      "An unexpected error occurred",
      status: :internal_server_error
    )
  end

  # Helper method for custom errors
  def render_api_error(error_code, message, status: :unprocessable_content, details: nil, suggestion: nil)
    response = {
      error: error_code,
      message: message
    }
    response[:details] = details if details.present?
    response[:suggestion] = suggestion if suggestion.present?
    response[:timestamp] = Time.current.iso8601

    render json: response, status: status
  end

  def render_plan_upgrade_required(required_plan:, current_plan:, message:, suggestion: nil)
    response = {
      error: "plan_upgrade_required",
      message: message,
      required_plan: required_plan.to_s,
      current_plan: current_plan.to_s,
      timestamp: Time.current.iso8601
    }
    response[:suggestion] = suggestion if suggestion.present?

    render json: response, status: :forbidden
  end

  def render_quota_exhausted(message, current_plan:, next_plan: nil, suggestion: nil)
    response = {
      error: "quota_exhausted",
      message: message,
      current_plan: current_plan.to_s,
      timestamp: Time.current.iso8601
    }
    response[:next_plan] = next_plan.to_s if next_plan.present?
    response[:suggestion] = suggestion if suggestion.present?

    render json: response, status: :unprocessable_content
  end

  # ==================== Convenience Error Methods ====================

  # 404 Not Found - resource doesn't exist
  def render_not_found(resource_name, details: nil)
    render_api_error(
      "not_found",
      "#{resource_name} not found",
      status: :not_found,
      details: details
    )
  end

  # 409 Conflict - resource already exists or state conflict
  def render_conflict(message, resource_id: nil, details: nil)
    extra_details = details || {}
    extra_details[:resource_id] = resource_id if resource_id.present?
    render_api_error(
      "conflict",
      message,
      status: :conflict,
      details: extra_details.presence
    )
  end

  # 422 Validation Failed - model validation errors
  def render_validation_failed(message, details: nil)
    render_api_error(
      "validation_failed",
      message,
      status: :unprocessable_content,
      details: details
    )
  end

  # 422 Invalid Request - missing/invalid parameters
  def render_invalid_request(message, details: nil)
    render_api_error(
      "invalid_request",
      message,
      status: :unprocessable_content,
      details: details
    )
  end

  # 422 Credentials Required - missing API credentials
  def render_credentials_required(message, suggestion: nil)
    render_api_error(
      "credentials_required",
      message,
      status: :unprocessable_content,
      suggestion: suggestion || "Configure credentials in the My Signer dashboard"
    )
  end

  # 422 Operation Failed - general operation failure
  def render_operation_failed(message, details: nil, suggestion: nil)
    render_api_error(
      "operation_failed",
      message,
      status: :unprocessable_content,
      details: details,
      suggestion: suggestion
    )
  end

  # 422 Invalid State - action not valid for current state
  def render_invalid_state(message, current_state: nil, details: nil)
    extra_details = details || {}
    extra_details[:current_state] = current_state if current_state.present?
    render_api_error(
      "invalid_state",
      message,
      status: :unprocessable_content,
      details: extra_details.presence
    )
  end

  # 422 External Error - third-party API error (Apple, Google)
  def render_external_error(message, details: nil, suggestion: nil)
    render_api_error(
      "external_error",
      message,
      status: :unprocessable_content,
      details: details,
      suggestion: suggestion
    )
  end

  # 422 Precondition Failed - required resources missing
  def render_precondition_failed(message, details: nil, suggestion: nil)
    render_api_error(
      "precondition_failed",
      message,
      status: :unprocessable_content,
      details: details,
      suggestion: suggestion
    )
  end

  # 403 Forbidden - not authorized for this action
  def render_forbidden_error(message = "You are not authorized to perform this action")
    render_api_error(
      "forbidden",
      message,
      status: :forbidden
    )
  end

  # 403 Insufficient Scope - token doesn't have required scope
  def render_insufficient_scope(required_scope)
    render_api_error(
      "insufficient_scope",
      "Token requires '#{required_scope}' scope",
      status: :forbidden,
      details: { required_scope: required_scope }
    )
  end

  # 401 Unauthorized - authentication required or failed
  def render_unauthorized(message = "Invalid or missing API token")
    render_api_error(
      "unauthorized",
      message,
      status: :unauthorized
    )
  end
end
