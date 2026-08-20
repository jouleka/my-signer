class CreateCustomProductPageVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_product_page_versions do |t|
      t.references :custom_product_page, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :remote_id, null: false
      t.string :state, null: false, default: "PREPARE_FOR_SUBMISSION"
      t.jsonb :raw_json, default: {}
      t.timestamps
    end
    add_index :custom_product_page_versions, :remote_id, unique: true
    add_index :custom_product_page_versions, [ :custom_product_page_id, :state ], name: "idx_cpp_versions_page_state"
  end
end
