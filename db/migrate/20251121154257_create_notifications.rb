class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :notification_type
      t.string :title
      t.text :message
      t.references :resource, polymorphic: true, null: false
      t.datetime :read_at
      t.datetime :dismissed_at

      t.timestamps
    end
  end
end
