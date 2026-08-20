class CreateAndroidKeystores < ActiveRecord::Migration[8.0]
  def change
    create_table :android_keystores do |t|
      t.references :organization, null: false, foreign_key: true
      t.bigint :android_app_id, null: true
      t.string :name, null: false
      t.binary :keystore_file, null: false
      t.string :keystore_password
      t.string :key_alias
      t.string :key_password
      t.date :expires_at
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :android_keystores, [ :organization_id, :name ], unique: true
    add_index :android_keystores, [ :organization_id, :active ]
    add_index :android_keystores, :android_app_id
  end
end
