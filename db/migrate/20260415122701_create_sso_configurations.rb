class CreateSsoConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :sso_configurations do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.string  :idp_entity_id,           null: false
      t.string  :idp_sso_target_url,      null: false
      t.string  :idp_slo_target_url
      t.text    :idp_cert                             # Encrypted via ActiveRecord::Encryption
      t.string  :name_identifier_format,  null: false,
                default: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
      t.jsonb   :attribute_mappings,      null: false, default: {}
      # role enum: admin=0, developer=1, viewer=2 (matches Membership)
      t.integer :jit_default_role,        null: false, default: 1
      t.boolean :enforced,                null: false, default: false
      t.boolean :enabled,                 null: false, default: false
      t.timestamps
    end
  end
end
