module AdvisoryLockable
  extend ActiveSupport::Concern

  private

  # Executes the block only if the PostgreSQL advisory lock can be acquired.
  # Uses pg_try_advisory_lock (non-blocking) so jobs skip rather than queue up.
  # The lock is automatically released when the block finishes.
  def with_advisory_lock(key)
    lock_id = Zlib.crc32(key.to_s)

    locked = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_try_advisory_lock(?)", lock_id ])
    )
    return unless locked

    begin
      yield
    ensure
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_unlock(?)", lock_id ])
      )
    end
  end
end
