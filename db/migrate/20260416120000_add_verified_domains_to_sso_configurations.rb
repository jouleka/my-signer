class AddVerifiedDomainsToSsoConfigurations < ActiveRecord::Migration[8.0]
  def change
    add_column :sso_configurations, :verified_domains, :text, array: true, null: false, default: []
  end
end
