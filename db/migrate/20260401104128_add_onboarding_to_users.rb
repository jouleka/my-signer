class AddOnboardingToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :onboarding_completed_at, :datetime
    add_column :users, :onboarding_step, :integer, default: 0, null: false
    add_column :users, :onboarding_platform, :string
  end
end
