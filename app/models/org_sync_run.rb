class OrgSyncRun < ApplicationRecord
  JOB_NAMES = %w[asc google_play reviews analytics cpp keywords_rank keywords_popularity].freeze
  STATUSES = %w[running ok partial error].freeze
  ERROR_MESSAGE_LIMIT = 500

  belongs_to :organization

  validates :job_name, presence: true, inclusion: { in: JOB_NAMES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :job_name, uniqueness: { scope: :organization_id }

  scope :for_org, ->(org_or_id) {
    where(organization_id: org_or_id.is_a?(Organization) ? org_or_id.id : org_or_id)
  }

  def self.record_started!(organization:, job_name:)
    job_name = job_name.to_s
    raise ArgumentError, "unknown job_name: #{job_name}" unless JOB_NAMES.include?(job_name)

    attrs = {
      status: "running",
      started_at: Time.current,
      finished_at: nil,
      error_message: nil
    }

    run = find_or_initialize_by(organization_id: organization.id, job_name: job_name)
    run.assign_attributes(attrs)
    begin
      run.save!
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # TOCTOU: another process inserted the (organization_id, job_name) row
      # between our find_or_initialize_by and save!. Depending on timing this
      # surfaces as RecordNotUnique (DB unique index) or RecordInvalid (the
      # app-level uniqueness validation sees the now-committed row). Either way,
      # re-find the existing row and update it in place. If no row exists, the
      # error was NOT a duplicate race (some other validation/DB failure) —
      # re-raise it rather than masking it.
      existing = find_by(organization_id: organization.id, job_name: job_name)
      raise e if existing.nil?

      existing.update!(attrs)
      run = existing
    end
    run
  end

  def self.record_finished!(organization:, job_name:, status:, error_message: nil)
    job_name = job_name.to_s
    status = status.to_s
    raise ArgumentError, "unknown job_name: #{job_name}" unless JOB_NAMES.include?(job_name)
    raise ArgumentError, "unknown status: #{status}" unless STATUSES.include?(status)

    run = find_by(organization_id: organization.id, job_name: job_name)
    return nil unless run

    run.update!(
      status: status,
      finished_at: Time.current,
      error_message: error_message&.to_s&.truncate(ERROR_MESSAGE_LIMIT)
    )
    run
  end

  def self.running?(organization_id:, job_name:)
    where(organization_id: organization_id, job_name: job_name.to_s, status: "running").exists?
  end
end
