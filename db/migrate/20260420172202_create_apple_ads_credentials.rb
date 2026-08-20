class CreateAppleAdsCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :apple_ads_credentials do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.string :client_id
      t.string :team_id
      t.string :key_id
      t.text :private_key_pem
      t.datetime :last_successful_at
      t.string :last_error, limit: 200
      t.timestamps
    end
  end
end
