require "rails_helper"

RSpec.describe Aso::RankCheckSchedulerJob, type: :job do
  include ActiveJob::TestHelper

  def create_org_with_tracked_keyword(plan_tier: :pro)
    user = create(:user, "#{plan_tier}_plan".to_sym)
    org = create(:organization, owner: user)
    app = create(:apple_app, organization: org)
    tk = create(:tracked_keyword, apple_app: app)
    create(:tracked_keyword_country, tracked_keyword: tk)
    org
  end

  describe "#perform" do
    it "enqueues one KeywordRankCheckJob per org that has tracked keywords" do
      org1 = create_org_with_tracked_keyword
      org2 = create_org_with_tracked_keyword
      # An org without any tracked keywords:
      create(:organization, owner: create(:user, :pro_plan))

      expect {
        described_class.new.perform
      }.to change { enqueued_jobs.size }.by(2)

      enqueued_org_ids = enqueued_jobs.map { |j| (j[:args].last[:organization_id] || j[:args].last["organization_id"]) }
      expect(enqueued_org_ids).to contain_exactly(org1.id, org2.id)
    end

    it "staggers enqueues across 22 hours" do
      create_org_with_tracked_keyword
      create_org_with_tracked_keyword
      create_org_with_tracked_keyword

      described_class.new.perform

      waits = enqueued_jobs.map { |j| j[:at] }.compact
      # all waits within 22 hours from now
      max_wait = 22.hours.from_now.to_f
      expect(waits).to all(be <= max_wait + 5) # fudge for clock
      # all waits in the future (non-negative delay from enqueue time)
      expect(waits).to all(be >= Time.current.to_f - 5)
    end

    it "uses the full 22-hour window for the random delay" do
      # Deterministically assert the upper bound of the rand range: if the
      # implementation ever silently shrinks the stagger window, the wait we
      # observe under a stubbed `rand(..max)` will no longer match 22h.
      create_org_with_tracked_keyword
      allow_any_instance_of(described_class).to receive(:rand) do |_, range|
        range.max
      end

      described_class.new.perform

      wait_at = enqueued_jobs.first[:at]
      expect(wait_at).to be_within(5.seconds.to_f).of(22.hours.from_now.to_f)
    end

    it "routes Team-tier orgs to aso_scraping_priority queue" do
      team_org = create_org_with_tracked_keyword(plan_tier: :team)
      described_class.new.perform
      priority_job = enqueued_jobs.find { |j| j[:queue] == "aso_scraping_priority" }
      expect(priority_job).to be_present
      expect(priority_job[:args].last[:organization_id] || priority_job[:args].last["organization_id"]).to eq(team_org.id)
    end

    it "routes Pro-tier orgs to aso_scraping queue" do
      pro_org = create_org_with_tracked_keyword(plan_tier: :pro)
      described_class.new.perform
      regular_job = enqueued_jobs.find { |j| j[:queue] == "aso_scraping" }
      expect(regular_job).to be_present
      expect(regular_job[:args].last[:organization_id] || regular_job[:args].last["organization_id"]).to eq(pro_org.id)
    end

    it "does not double-enqueue an org with multiple apps/keywords" do
      org = create_org_with_tracked_keyword
      # Add a second app with a tracked keyword:
      app2 = create(:apple_app, organization: org, sku: "sku-2")
      tk2 = create(:tracked_keyword, apple_app: app2)
      create(:tracked_keyword_country, tracked_keyword: tk2)

      described_class.new.perform
      expect(enqueued_jobs.size).to eq(1)
    end
  end
end
