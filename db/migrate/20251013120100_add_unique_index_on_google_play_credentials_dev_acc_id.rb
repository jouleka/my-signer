class AddUniqueIndexOnGooglePlayCredentialsDevAccId < ActiveRecord::Migration[8.0]
  def change
    add_index :google_play_credentials,
              [ :organization_id, :developer_account_id ],
              unique: true,
              where: "developer_account_id IS NOT NULL",
              name: "idx_unique_gp_dev_acc_per_org"
  end
end
