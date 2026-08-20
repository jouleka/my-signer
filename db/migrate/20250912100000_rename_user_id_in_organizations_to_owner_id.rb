class RenameUserIdInOrganizationsToOwnerId < ActiveRecord::Migration[8.0]
  def change
    rename_column :organizations, :user_id, :owner_id
  end
end
