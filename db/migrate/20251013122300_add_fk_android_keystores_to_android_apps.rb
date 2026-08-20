class AddFkAndroidKeystoresToAndroidApps < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :android_keystores, :android_apps
  end
end
