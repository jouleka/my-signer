class AddPartialUniqueIndexToUsersProviderUid < ActiveRecord::Migration[8.0]
  # Defense-in-depth backstop for the OAuth identity-hijack class. The
  # primary fix lives in Users::RegistrationsController#update_resource
  # (strong-params now strips non-blank provider/uid before the update).
  # This index closes the window where any future write path -- a
  # console one-liner, an admin tool, a rake task, a service that
  # bypasses update_resource via update_columns -- could land a
  # duplicate (provider, uid) tuple and revive the hijack class.
  #
  # Partial WHERE clause notes:
  # - `provider IS NOT NULL AND uid IS NOT NULL`: an email/password
  #   account with no SSO ever linked has both columns NULL. Multiple
  #   such users must coexist; the index excludes them.
  # - `provider <> '' AND uid <> ''`: the settings "Disconnect SSO"
  #   modal submits both fields via `f.hidden_field :provider,
  #   value: nil` which renders an empty string. After Devise's
  #   `update_with_password`, the row is left with provider="" and
  #   uid="". Multiple disconnected users must coexist; the index
  #   excludes empty-string rows too.
  #
  # `algorithm: :concurrently` requires `disable_ddl_transaction!`.
  # `users` is hot enough that an ACCESS EXCLUSIVE lock on a non-
  # concurrent index build can stall every authenticated request
  # mid-deploy. Mirrors the pattern in
  # 20260501182032_add_soft_delete_to_users.
  disable_ddl_transaction!

  def up
    add_index :users, [ :provider, :uid ],
      unique: true,
      where: "provider IS NOT NULL AND provider <> '' AND uid IS NOT NULL AND uid <> ''",
      name: "index_users_on_provider_and_uid_unique",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :users,
      name: "index_users_on_provider_and_uid_unique",
      algorithm: :concurrently,
      if_exists: true
  end
end
