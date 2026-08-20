class AddTrialFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :trial_started_at, :datetime
    add_column :users, :trial_ends_at, :datetime

    # trial_ends_at is queried daily by TrialExpirationJob and TrialReminderJob.
    # An index on this column is essential for those queries to remain fast
    # as the user table grows.
    add_index :users, :trial_ends_at
  end
end
