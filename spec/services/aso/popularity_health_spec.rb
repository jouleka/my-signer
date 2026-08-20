require "rails_helper"

RSpec.describe Aso::PopularityHealth do
  let(:user) { create(:user, :pro_plan) }
  let(:org) { create(:organization, owner: user) }
  let(:app) { create(:apple_app, organization: org) }
  let(:credential) { create(:apple_ads_credential, organization: org, last_successful_at: 1.hour.ago) }

  describe ".for" do
    it "returns healthy when no credential is connected" do
      app  # ensure no credential exists
      report = described_class.for(organization: org)
      expect(report).to be_healthy
      expect(report).not_to be_stale
      expect(report).not_to be_collapsed
    end

    it "returns healthy when credential exists but has never succeeded" do
      create(:apple_ads_credential, organization: org, last_successful_at: nil)
      app
      report = described_class.for(organization: org)
      expect(report).to be_healthy
    end

    it "returns healthy when credential connected but no tracked keywords yet" do
      credential; app
      report = described_class.for(organization: org)
      expect(report).to be_healthy
    end

    it "detects stale when last refresh > 72 hours ago" do
      credential
      create(:tracked_keyword, apple_app: app, search_popularity: 50,
             search_popularity_updated_at: 4.days.ago)
      report = described_class.for(organization: org)
      expect(report).to be_stale
    end

    it "does NOT flag stale when last refresh within 72 hours" do
      credential
      create(:tracked_keyword, apple_app: app, search_popularity: 50,
             search_popularity_updated_at: 2.hours.ago)
      report = described_class.for(organization: org)
      expect(report).not_to be_stale
    end

    it "detects collapse when >80% of values are at max (100) and sample >= 10" do
      credential
      9.times { |i| create(:tracked_keyword, apple_app: app, keyword: "kw-max-#{i}", search_popularity: 100, search_popularity_updated_at: 1.hour.ago) }
      2.times { |i| create(:tracked_keyword, apple_app: app, keyword: "kw-other-#{i}", search_popularity: 50, search_popularity_updated_at: 1.hour.ago) }
      # 11 total, 9 at max = 81.8%
      report = described_class.for(organization: org)
      expect(report).to be_collapsed
      expect(report.collapse_ratio).to be_within(0.01).of(9.0 / 11)
      expect(report.sample_size).to eq(11)
    end

    it "does NOT flag collapse with sample size < 10" do
      credential
      5.times { |i| create(:tracked_keyword, apple_app: app, keyword: "kw-max-#{i}", search_popularity: 100, search_popularity_updated_at: 1.hour.ago) }
      report = described_class.for(organization: org)
      expect(report).not_to be_collapsed
    end

    it "does NOT flag collapse when <80% at max" do
      credential
      7.times { |i| create(:tracked_keyword, apple_app: app, keyword: "kw-max-#{i}", search_popularity: 100, search_popularity_updated_at: 1.hour.ago) }
      4.times { |i| create(:tracked_keyword, apple_app: app, keyword: "kw-other-#{i}", search_popularity: 50, search_popularity_updated_at: 1.hour.ago) }
      # 11 total, 7 at max = 63.6% < 80%
      report = described_class.for(organization: org)
      expect(report).not_to be_collapsed
    end

    it "can be both stale AND collapsed at once" do
      credential
      10.times { |i| create(:tracked_keyword, apple_app: app, keyword: "kw-#{i}", search_popularity: 100, search_popularity_updated_at: 4.days.ago) }
      report = described_class.for(organization: org)
      expect(report).to be_stale
      expect(report).to be_collapsed
      expect(report).not_to be_healthy
    end

    it "scopes the sample to the requesting org's apps" do
      credential
      # 10 collapsed keywords belong to a DIFFERENT org's app
      other_user = create(:user, :pro_plan)
      other_org = create(:organization, owner: other_user)
      other_app = create(:apple_app, organization: other_org)
      10.times { |i| create(:tracked_keyword, apple_app: other_app, keyword: "other-kw-#{i}", search_popularity: 100, search_popularity_updated_at: 1.hour.ago) }
      # The requesting org has nothing tracked
      app
      report = described_class.for(organization: org)
      expect(report).to be_healthy
    end
  end
end
