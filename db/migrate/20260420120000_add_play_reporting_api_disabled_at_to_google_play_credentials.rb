class AddPlayReportingApiDisabledAtToGooglePlayCredentials < ActiveRecord::Migration[8.0]
  def change
    # Stamped when we detect a 403 SERVICE_DISABLED from
    # playdeveloperreporting.googleapis.com for this credential.
    # Cleared back to NULL on the next successful Vitals call.
    # The UI reads this column to render a "Enable the API" banner with
    # a click-through to the Google Cloud Console, scoped to the project
    # that owns the service-account credential.
    add_column :google_play_credentials, :play_reporting_api_disabled_at, :datetime
  end
end
