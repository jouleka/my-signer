class CreateAndroidApps < ActiveRecord::Migration[8.0]
  def change
    create_table :android_apps do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :package_name, null: false
      t.string :name
      t.string :default_language
      t.jsonb :raw_json, default: {}
      t.timestamps
    end

    add_index :android_apps, [ :organization_id, :package_name ], unique: true
  end
end
