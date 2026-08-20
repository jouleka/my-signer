class CreateOrgSyncRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :org_sync_runs do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :job_name, null: false
      t.string :status, null: false, default: "running"
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.timestamps
    end

    add_index :org_sync_runs, [ :organization_id, :job_name ], unique: true
    add_index :org_sync_runs, :job_name
  end
end
