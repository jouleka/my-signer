class CreateAppStoreConnectCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :app_store_connect_credentials do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name
      t.string :key_id
      t.string :issuer_id
      t.text :private_key

      t.timestamps
    end
  end
end
