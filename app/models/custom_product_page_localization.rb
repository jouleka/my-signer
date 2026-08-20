class CustomProductPageLocalization < ApplicationRecord
  belongs_to :custom_product_page_version
  belongs_to :organization

  validates :remote_id, presence: true, uniqueness: true
  validates :locale, presence: true
  validates :locale, uniqueness: { scope: :custom_product_page_version_id }
end
