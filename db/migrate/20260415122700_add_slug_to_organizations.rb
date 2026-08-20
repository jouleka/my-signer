class AddSlugToOrganizations < ActiveRecord::Migration[8.0]
  def up
    add_column :organizations, :slug, :string
    add_index  :organizations, :slug, unique: true

    # Backfill slugs for existing orgs. The slug is used in SSO URLs
    # (/users/auth/saml/:slug) so every org needs a unique value before we
    # flip the NOT NULL constraint.
    Organization.reset_column_information
    Organization.find_each do |org|
      base = org.name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      base = "org-#{org.id}" if base.blank?

      candidate = base
      suffix = 1
      while Organization.where.not(id: org.id).exists?(slug: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end
      org.update_column(:slug, candidate)
    end

    change_column_null :organizations, :slug, false
  end

  def down
    remove_index  :organizations, :slug
    remove_column :organizations, :slug
  end
end
