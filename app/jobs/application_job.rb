class ApplicationJob < ActiveJob::Base
  # Retry on transient database/network errors (critical for Solid Queue in production
  # which has no built-in retry unless retry_on is declared via ActiveJob)
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5
  retry_on ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
