class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.text :scopes, default: "read"
      t.datetime :last_used_at
      t.datetime :expires_at
      t.boolean :revoked, default: false, null: false

      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
    add_index :api_tokens, [ :organization_id, :revoked ]
    add_index :api_tokens, [ :user_id, :revoked ]
  end
end
