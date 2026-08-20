class AddTeamIdToAppleResources < ActiveRecord::Migration[8.0]
  def change
    add_column :apple_certificates, :team_id, :string
    add_column :apple_devices, :team_id, :string
    add_column :apple_provisioning_profiles, :team_id, :string
    add_column :apple_bundle_ids, :team_id, :string

    add_index :apple_certificates, [ :organization_id, :team_id ]
    add_index :apple_devices, [ :organization_id, :team_id ]
    add_index :apple_provisioning_profiles, [ :organization_id, :team_id ]
    add_index :apple_bundle_ids, [ :organization_id, :team_id ]
  end
end
