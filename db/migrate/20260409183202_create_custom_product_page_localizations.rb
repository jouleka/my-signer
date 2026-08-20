class CreateCustomProductPageLocalizations < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_product_page_localizations do |t|
      t.references :custom_product_page_version, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :remote_id, null: false
      t.string :locale, null: false
      t.string :promotional_text
      t.jsonb :raw_json, default: {}
      t.timestamps
    end
    add_index :custom_product_page_localizations, :remote_id, unique: true
    add_index :custom_product_page_localizations, [ :custom_product_page_version_id, :locale ],
              unique: true, name: "idx_cpp_locs_version_locale"
  end
end
