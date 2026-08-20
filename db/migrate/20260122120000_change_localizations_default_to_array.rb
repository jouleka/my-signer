# frozen_string_literal: true

class ChangeLocalizationsDefaultToArray < ActiveRecord::Migration[8.0]
  def up
    # Change default from {} to []
    change_column_default :app_store_releases, :localizations, from: {}, to: []
    change_column_default :play_store_releases, :localizations, from: {}, to: []

    # Migrate existing records: convert {} to [], keep valid arrays intact
    execute <<-SQL
      UPDATE app_store_releases
      SET localizations = '[]'::jsonb
      WHERE localizations = '{}'::jsonb OR localizations IS NULL
    SQL

    execute <<-SQL
      UPDATE play_store_releases
      SET localizations = '[]'::jsonb
      WHERE localizations = '{}'::jsonb OR localizations IS NULL
    SQL
  end

  def down
    change_column_default :app_store_releases, :localizations, from: [], to: {}
    change_column_default :play_store_releases, :localizations, from: [], to: {}

    # Optionally convert empty arrays back to empty objects
    execute <<-SQL
      UPDATE app_store_releases
      SET localizations = '{}'::jsonb
      WHERE localizations = '[]'::jsonb
    SQL

    execute <<-SQL
      UPDATE play_store_releases
      SET localizations = '{}'::jsonb
      WHERE localizations = '[]'::jsonb
    SQL
  end
end
