require "rails_helper"

RSpec.describe Aso::KeywordHistoryRetentionJob do
  let(:free_org) { create(:organization, owner: create(:user)) }
  let(:pro_org)  { create(:organization, owner: create(:user, :pro_plan)) }
  let(:team_org) { create(:organization, owner: create(:user, :team_plan)) }

  # AppleApp#squish_fields coerces a nil sku to "" before validation, so the
  # uniqueness-scoped-to-organization validator treats multiple factory calls
  # with no sku as a collision inside a single org. Passing an explicit unique
  # sku sidesteps that without touching the global factory default.
  def seed(org, days_ago:)
    app = create(:apple_app, organization: org, sku: "sku-#{SecureRandom.hex(4)}")
    tk  = create(:tracked_keyword, apple_app: app)
    tkc = create(:tracked_keyword_country, tracked_keyword: tk)
    KeywordRanking.create!(
      organization: org,
      tracked_keyword_country: tkc,
      keyword: tk.keyword,
      rank: 5,
      checked_on: days_ago.days.ago.to_date
    )
  end

  it "deletes Free-tier rankings older than 7 days" do
    seed(free_org, days_ago: 100)
    seed(free_org, days_ago: 10)
    seed(free_org, days_ago: 1)

    described_class.new.perform

    remaining = KeywordRanking.where(organization_id: free_org.id)
    expect(remaining.count).to eq(1)
    expect(remaining.pluck(:checked_on)).to contain_exactly(1.day.ago.to_date)
  end

  it "deletes Pro-tier rankings older than 90 days" do
    seed(pro_org, days_ago: 100)
    seed(pro_org, days_ago: 10)
    seed(pro_org, days_ago: 1)

    described_class.new.perform

    expect(KeywordRanking.where(organization_id: pro_org.id).count).to eq(2)
  end

  it "keeps Team-tier rankings within 365 days" do
    seed(team_org, days_ago: 400)
    seed(team_org, days_ago: 10)

    described_class.new.perform

    team_rankings = KeywordRanking.where(organization_id: team_org.id)
    expect(team_rankings.count).to eq(1)
    expect(team_rankings.first.checked_on).to eq(10.days.ago.to_date)
  end

  it "uses batched deletes" do
    seed(free_org, days_ago: 100)
    10.times { |i| seed(free_org, days_ago: 100 + i) }

    # Spy on #in_batches across every AR relation instance. Using
    # expect_any_instance_of here would assert on a single instance, but
    # find_each itself uses in_batches internally and the per-org scoped
    # KeywordRanking query is a separate relation — so we need a spy that
    # tolerates repeated receivers. Rails' ActiveRecord::Batches is the
    # module that actually defines in_batches, so we patch it there.
    call_count = 0
    original = ActiveRecord::Batches.instance_method(:in_batches)
    ActiveRecord::Batches.define_method(:in_batches) do |**opts, &blk|
      call_count += 1
      original.bind(self).call(**opts, &blk)
    end

    begin
      described_class.new.perform
    ensure
      ActiveRecord::Batches.define_method(:in_batches, original)
    end

    expect(call_count).to be >= 1
  end

  it "is queued on :default" do
    expect(described_class.new.queue_name).to eq("default")
  end
end
