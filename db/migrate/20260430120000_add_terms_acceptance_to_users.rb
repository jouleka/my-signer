class AddTermsAcceptanceToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :terms_accepted_at, :datetime
    add_column :users, :marketing_emails_opt_in, :boolean, default: false, null: false
  end
end
