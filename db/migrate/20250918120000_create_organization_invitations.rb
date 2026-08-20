class CreateOrganizationInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :organization_invitations do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.integer :role, null: false, default: 1 # developer by default
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :organization_invitations, :token, unique: true
    add_index :organization_invitations, [ :organization_id, :email, :accepted_at, :cancelled_at ], name: "index_org_invites_uniquish"
  end
end
