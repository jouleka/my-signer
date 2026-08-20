class AddRevokedAtToApiTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :api_tokens, :revoked_at, :datetime
    add_index :api_tokens, :revoked_at
  end
end
