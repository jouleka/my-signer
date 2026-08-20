class SyncChangeDetector
  attr_reader :organization, :changes

  def initialize(organization)
    @organization = organization
    @changes = []
  end

  def snapshot_before
    @before = capture_counts
  end

  def detect_changes
    after = capture_counts
    @changes = []

    @before.each do |resource_type, before_count|
      after_count = after[resource_type] || 0
      diff = after_count - before_count

      if diff > 0
        @changes << "#{diff} new #{resource_type.underscore.humanize.downcase.pluralize(diff)}"
      elsif diff < 0
        @changes << "#{diff.abs} #{resource_type.underscore.humanize.downcase.pluralize(diff.abs)} removed"
      end
    end

    @changes
  end

  def changes?
    @changes.any?
  end

  def total_changes
    return 0 unless @before
    after = capture_counts
    @before.sum { |type, count| (after[type] || 0) - count }.abs
  end

  private

  def capture_counts
    {
      "AppleCertificate" => @organization.apple_certificates.count,
      "AppleProvisioningProfile" => @organization.apple_provisioning_profiles.count,
      "AppleBundleId" => @organization.apple_bundle_ids.count,
      "AppleDevice" => @organization.apple_devices.count,
      "AppleApp" => @organization.apple_apps.count
    }
  end
end
