class AddDeepLinkToCustomProductPageVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :custom_product_page_versions, :deep_link, :string
  end
end
