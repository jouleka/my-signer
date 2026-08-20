module AppleApps
  # Lightweight form object that adapts AppleApp#cli_defaults for the legacy
  # _form.html.erb partial. The partial was originally written against
  # AppStoreRelease, so it reads `auto_submit`, `version_string`, etc.
  # directly on the form's model. This PORO mirrors that interface without
  # requiring an AR model, so the partial's field helpers (f.text_field,
  # f.radio_button, f.check_box) work unchanged.
  #
  # `model_name` is pinned to "AppStoreRelease" so form param keys stay nested
  # under `app_store_release[...]`, matching the existing controller strong-
  # params. This keeps the form backward compatible with any existing clients.
  class CliDefaultsForm
    include ActiveModel::Model

    attr_accessor :auto_submit,
                  :phased_release,
                  :version_string,
                  :build_number,
                  :release_type,
                  :earliest_release_date,
                  :apple_bundle_id_id

    def self.from_apple_app(apple_app, defaults: {})
      form = new
      if apple_app
        form.auto_submit          = apple_app.cli_auto_submit?
        form.phased_release       = apple_app.cli_phased_release?
        form.version_string       = apple_app.cli_version_string
        form.build_number         = apple_app.cli_build_number
        form.release_type         = apple_app.cli_release_type
        form.earliest_release_date = apple_app.cli_earliest_release_date
        form.apple_bundle_id_id   = apple_app.apple_bundle_id_record&.id
      end
      form.assign_attributes(defaults) if defaults.any?
      form
    end

    def persisted? = false

    def to_model = self
    def to_key    = nil

    # Renders field names as `app_store_release[field]` so the controller's
    # strong-params continue to work unchanged.
    def self.model_name
      @_model_name ||= ActiveModel::Name.new(self, nil, "AppStoreRelease")
    end

    # Copies the model-side CLI defaults errors onto this form object so
    # `form.errors.full_messages` renders them in the shared error card.
    def copy_errors_from(apple_app)
      apple_app.cli_defaults_errors.each do |field, message|
        errors.add(field, message)
      end
      self
    end
  end
end
