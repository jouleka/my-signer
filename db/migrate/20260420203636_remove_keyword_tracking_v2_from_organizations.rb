class RemoveKeywordTrackingV2FromOrganizations < ActiveRecord::Migration[8.0]
  # Phase C cleanup: retires the per-org rollout flag. During canary (Task 21)
  # the column gated the Tracking tab, Apple Search Ads integration, and the
  # scheduler fan-outs. Phase 5 completed the rollout; every surface is now
  # either permanently on or entitlement-gated, so the column is dead weight.
  def change
    remove_column :organizations, :keyword_tracking_v2, :boolean, default: false, null: false
  end
end
