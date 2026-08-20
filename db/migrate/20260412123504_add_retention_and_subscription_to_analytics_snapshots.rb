class AddRetentionAndSubscriptionToAnalyticsSnapshots < ActiveRecord::Migration[8.0]
  def change
    # Retention metrics (percentages, opt-in only from Apple)
    add_column :app_analytics_snapshots, :retention_day_1, :decimal, precision: 5, scale: 2
    add_column :app_analytics_snapshots, :retention_day_7, :decimal, precision: 5, scale: 2
    add_column :app_analytics_snapshots, :retention_day_14, :decimal, precision: 5, scale: 2
    add_column :app_analytics_snapshots, :retention_day_28, :decimal, precision: 5, scale: 2

    # Subscription metrics (from Apple COMMERCE reports)
    add_column :app_analytics_snapshots, :active_subscriptions, :integer, default: 0
    add_column :app_analytics_snapshots, :new_subscriptions, :integer, default: 0
    add_column :app_analytics_snapshots, :churned_subscriptions, :integer, default: 0
    add_column :app_analytics_snapshots, :trial_starts, :integer, default: 0
    add_column :app_analytics_snapshots, :trial_conversions, :integer, default: 0
    add_column :app_analytics_snapshots, :proceeds, :decimal, precision: 10, scale: 2

    # Installs/deletions (from Apple APP_USAGE)
    add_column :app_analytics_snapshots, :installs, :integer, default: 0
    add_column :app_analytics_snapshots, :deletions, :integer, default: 0
  end
end
