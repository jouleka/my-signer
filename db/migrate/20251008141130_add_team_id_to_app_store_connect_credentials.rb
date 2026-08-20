class AddTeamIdToAppStoreConnectCredentials < ActiveRecord::Migration[8.0]
  def change
    add_column :app_store_connect_credentials, :team_id, :string
  end
end
