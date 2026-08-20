class AddSubmissionFieldsToCustomProductPageVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :custom_product_page_versions, :submission_status, :string
    add_column :custom_product_page_versions, :submission_error, :text
  end
end
