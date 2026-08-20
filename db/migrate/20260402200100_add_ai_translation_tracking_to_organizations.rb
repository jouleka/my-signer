class AddAiTranslationTrackingToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :ai_translations_count, :integer, default: 0, null: false
    add_column :organizations, :ai_translations_reset_at, :datetime
  end
end
