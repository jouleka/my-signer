class ReviewSyncJob < ApplicationJob
  include AdvisoryLockable
  include SyncRunTrackable

  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(organization_id:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    with_advisory_lock("reviews:sync:org:#{organization.id}") do
      track_sync_run(organization: organization, job_name: :reviews) do
        entitlements = organization.entitlements
        next unless entitlements.review_monitoring_enabled?

        max_apps = entitlements.max_review_monitoring_apps
        ReviewSync::Performer.new(organization: organization, max_apps: max_apps).call

        allowed_apple = organization.apple_apps.order(:created_at).limit(max_apps)
        remaining = [ max_apps - allowed_apple.count, 0 ].max
        allowed_android = remaining > 0 ? organization.android_apps.order(:created_at).limit(remaining) : AndroidApp.none

        allowed_apple.find_each { |app| take_snapshot(organization, app) }
        allowed_android.find_each { |app| take_snapshot(organization, app) }
      end
    end
  end

  private

  def take_snapshot(organization, app)
    reviews = app.app_reviews
    total = reviews.count
    return if total.zero?

    avg = reviews.average(:rating).to_f.round(2)
    counts = reviews.group(:rating).count

    RatingSnapshot.upsert(
      {
        organization_id: organization.id,
        snapshotable_type: app.class.name,
        snapshotable_id: app.id,
        snapshot_date: Date.current,
        average_rating: avg,
        review_count: total,
        rating_1_count: counts[1] || 0,
        rating_2_count: counts[2] || 0,
        rating_3_count: counts[3] || 0,
        rating_4_count: counts[4] || 0,
        rating_5_count: counts[5] || 0,
        created_at: Time.current,
        updated_at: Time.current
      },
      unique_by: %i[snapshotable_type snapshotable_id snapshot_date]
    )
  end
end
