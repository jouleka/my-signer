class AddLastOrganizationToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :last_organization, foreign_key: { to_table: :organizations }
  end
end
