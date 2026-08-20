FactoryBot.define do
  factory :asc_build_upload do
    organization
    apple_app { create(:apple_app, organization: organization) }
    user { organization.owner }
    sequence(:remote_id)      { |n| "remote-upload-#{n}-#{SecureRandom.hex(4)}" }
    sequence(:remote_file_id) { |n| "remote-file-#{n}-#{SecureRandom.hex(4)}" }
    cf_bundle_version { "1" }
    cf_bundle_short_version_string { "1.0.0" }
    platform { "IOS" }
    file_name { "app.ipa" }
    file_size { 10_000_000 }
    state { "pending" }
  end
end
