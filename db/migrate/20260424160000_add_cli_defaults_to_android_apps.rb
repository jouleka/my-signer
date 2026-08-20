class AddCliDefaultsToAndroidApps < ActiveRecord::Migration[8.0]
  # Mirrors the apple_apps.cli_defaults column — per-app knobs that
  # `mysigner ship android` reads at submission time. Keys are documented
  # in AndroidApp::CLI_DEFAULT_KEYS.
  def change
    add_column :android_apps, :cli_defaults, :jsonb, default: {}, null: false
  end
end
