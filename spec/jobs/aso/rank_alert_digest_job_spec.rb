require "rails_helper"

RSpec.describe Aso::RankAlertDigestJob, type: :job do
  include ActiveJob::TestHelper

  let(:team_org) { create(:organization, owner: create(:user, :team_plan)) }
  let(:pro_org)  { create(:organization, owner: create(:user, :pro_plan)) }

  # The apple_app factory gets explicit unique SKUs to avoid tripping the
  # squish_fields-induced "" collision on scoped uniqueness (same quirk the
  # retention spec works around).
  def make_app(org)
    create(:apple_app, organization: org, sku: "sku-#{SecureRandom.hex(4)}")
  end

  it "sends no mail for orgs without keyword_rank_alerts_enabled?" do
    # Seed a movement that would be significant if the tier gate were open,
    # to prove the gate — not the movement detector — is what skips pro_org.
    app = make_app(pro_org)
    tk  = create(:tracked_keyword, apple_app: app)
    tkc = create(:tracked_keyword_country, tracked_keyword: tk, current_rank: 5)
    KeywordRanking.create!(
      organization: pro_org, tracked_keyword_country: tkc,
      keyword: tk.keyword, rank: 30, checked_on: 7.days.ago.to_date
    )

    expect { described_class.new.perform }.not_to change(ActionMailer::Base.deliveries, :count)
  end

  it "sends digest to Team-tier org admins when significant movements exist" do
    app = make_app(team_org)
    tk  = create(:tracked_keyword, apple_app: app)
    tkc = create(:tracked_keyword_country, tracked_keyword: tk, current_rank: 5) # entered top 10
    KeywordRanking.create!(
      organization: team_org, tracked_keyword_country: tkc,
      keyword: tk.keyword, rank: 30, checked_on: 7.days.ago.to_date
    )

    expect { described_class.new.perform }.to change(ActionMailer::Base.deliveries, :count).by_at_least(1)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.subject).to include(team_org.name)
    expect(mail.to).to include(team_org.owner.email)
  end

  it "sends no digest when no significant movements" do
    app = make_app(team_org)
    tk  = create(:tracked_keyword, apple_app: app)
    tkc = create(:tracked_keyword_country, tracked_keyword: tk, current_rank: 25)
    KeywordRanking.create!(
      organization: team_org, tracked_keyword_country: tkc,
      keyword: tk.keyword, rank: 27, checked_on: 7.days.ago.to_date
    )

    expect { described_class.new.perform }.not_to change(ActionMailer::Base.deliveries, :count)
  end
end
