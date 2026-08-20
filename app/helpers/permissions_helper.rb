module PermissionsHelper
  # Canonical role-permission matrix displayed on the permissions page.
  # Mirrors the checks defined across our Pundit policies -- update both
  # when roles gain/lose capabilities.
  #
  # The :key field is a stable identifier consumed by
  # spec/helpers/permissions_helper_spec.rb to assert that each row's
  # role booleans match the corresponding Pundit policy method's actual
  # return value. Changing a key requires a matching update in the spec's
  # mapping table; changing a row's role values without updating the
  # underlying policy (or vice versa) will cause that spec to fail.
  def permission_matrix
    [
      { key: :view_org_data,       label: "View org data",          hint: "See apps, reviews, analytics, keywords",
        viewer: true,  developer: true,  admin: true,  owner: true },
      { key: :sync_stores,         label: "Sync from stores",       hint: "Manually trigger syncs from App Store Connect / Google Play",
        viewer: false, developer: true,  admin: true,  owner: true },
      { key: :edit_store_listings, label: "Edit store listings",    hint: "Update metadata, release notes, screenshots",
        viewer: false, developer: true,  admin: true,  owner: true },
      { key: :push_to_stores,      label: "Push to stores",         hint: "Push changes directly to App Store or Google Play",
        viewer: false, developer: true,  admin: true,  owner: true },
      { key: :ai_translate,        label: "AI translate / rewrite", hint: "Use AI to translate or improve listing copy",
        viewer: false, developer: true,  admin: true,  owner: true },
      { key: :invite_members,      label: "Invite members",         hint: "Invite developer/viewer roles (admin role requires admin)",
        viewer: false, developer: true,  admin: true,  owner: true },
      { key: :create_api_tokens,   label: "Create API tokens",      hint: "Create read / write API tokens (admin scope requires admin)",
        viewer: false, developer: true,  admin: true,  owner: true },
      { key: :manage_credentials,  label: "Manage credentials",     hint: "App Store Connect, Google Play service accounts",
        viewer: false, developer: false, admin: true,  owner: true },
      { key: :manage_apple_ads_credential, label: "Manage Apple Search Ads credential", hint: "Connect / rotate / remove the Apple Ads integration key",
        viewer: false, developer: false, admin: true,  owner: true },
      { key: :track_keywords,      label: "Track keywords",          hint: "Add keywords for rank monitoring (Pro+)",
        viewer: true,  developer: true,  admin: true,  owner: true },
      { key: :remove_tracked_keywords, label: "Remove tracked keywords", hint: "Delete keyword entries (allowed even after downgrade for cleanup)",
        viewer: true,  developer: true,  admin: true,  owner: true },
      { key: :change_member_roles, label: "Change member roles",    hint: "Promote or demote team members",
        viewer: false, developer: false, admin: true,  owner: true },
      { key: :invite_admins,       label: "Invite admins",          hint: "Invite new members with admin role",
        viewer: false, developer: false, admin: true,  owner: true },
      { key: :delete_store_listings, label: "Delete store listings", hint: "Remove store listings from the organization",
        viewer: false, developer: false, admin: true,  owner: true },
      { key: :view_audit_log,      label: "View audit log",         hint: "See sensitive actions (Team plan only)",
        viewer: false, developer: false, admin: true,  owner: true },
      { key: :delete_organization, label: "Delete organization",    hint: "Permanently delete the org and all its data",
        viewer: false, developer: false, admin: false, owner: true }
    ].freeze
  end
end
