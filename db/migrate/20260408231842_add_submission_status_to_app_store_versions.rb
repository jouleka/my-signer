class AddSubmissionStatusToAppStoreVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :app_store_versions, :submission_status, :string
    add_column :app_store_versions, :submission_error, :text
    add_index :app_store_versions, :submission_status,
              where: "submission_status = 'submitting'",
              name: "index_app_store_versions_on_submitting"
  end
end
