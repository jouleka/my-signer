class AddTrialRemindersSentToUsers < ActiveRecord::Migration[8.0]
  def change
    # Tracks which trial reminder milestones have been sent to each user so
    # TrialReminderJob can prevent duplicate emails if it's retried on the
    # same day. The jsonb shape is {"7"=>"2026-04-15", "3"=>"2026-04-19"} etc.
    # Timezone-naive string dates are fine -- we only need "was this sent
    # already?" semantics, not precise timing.
    add_column :users, :trial_reminders_sent, :jsonb, null: false, default: {}
  end
end
