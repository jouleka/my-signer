require "rails_helper"

# System coverage for the Tracking tab's card rank-state rendering and the
# turbo-frame lazy-load of the per-keyword detail (rank history chart).
#
# Exercises both bug reports resolved in 2026-04 polish pass:
#   - Bug 1: "Not in top 250" leaking into freshly-added rows that have never
#     been checked. The card must now render "Queued" for last_checked_at.nil?.
#   - Bug 2: Clicking a keyword card did not populate the detail frame. The
#     card embeds an empty <turbo-frame id="tk-detail-<id>"> that the link's
#     data-turbo-frame targets; on click, TrackedKeywordsController#show
#     must return a matching <turbo-frame> wrapper so Turbo can swap it in.
RSpec.describe "Keyword tracking detail expand", type: :system, js: true do
  let(:user) { create(:user, :pro_plan) }
  let(:org)  { create(:organization, owner: user) }
  let(:app)  { create(:apple_app, organization: org, name: "My App") }
  let!(:tk)  { create(:tracked_keyword, apple_app: app, keyword: "photo editor") }
  let!(:tkc) { create(:tracked_keyword_country, tracked_keyword: tk, country: "us") }

  before { sign_in user }

  it "shows 'Queued' for never-checked keywords and suppresses the 'Not in top 250' placeholder" do
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "tracking")
    expect(page).to have_content("Queued")
    expect(page).not_to have_content("Not in top 250")
  end

  it "shows 'Not in top 250' for a checked-but-unranked keyword" do
    tkc.update!(last_checked_at: 2.hours.ago, current_rank: nil)
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "tracking")
    expect(page).to have_content("Not in top 250")
    expect(page).not_to have_content("Queued")
  end

  it "shows the rank position when ranked" do
    tkc.update!(last_checked_at: 1.hour.ago, current_rank: 12)
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "tracking")
    expect(page).to have_content("#12")
  end

  it "expands the detail frame in place when the card link is clicked" do
    # Seed a ranking so the detail partial renders a per-country history card.
    KeywordRanking.create!(
      organization: org,
      tracked_keyword_country: tkc,
      keyword: tk.keyword,
      rank: 5,
      checked_on: 2.days.ago.to_date
    )
    visit organization_keyword_path(org, "apple_app_#{app.id}", tab: "tracking")

    # Pre-click the tracking tab and Add-keyword button should both be
    # present (they live outside the turbo-frame we're expanding).
    expect(page).to have_button("Add keyword")

    # Click on the keyword text -- the anchor whose data-turbo-frame
    # targets tk-detail-<id>. Turbo must intercept and swap only the
    # frame, leaving the rest of the tracking tab mounted.
    click_on "photo editor"

    # Frame and chart should appear, without leaving the tracking tab.
    expect(page).to have_css("turbo-frame#tk-detail-#{tk.id}", wait: 5)
    expect(page).to have_css("canvas[data-controller='keyword-rank-chart']", wait: 5)

    # Sanity: we are still on the tracking tab (Add-keyword button still
    # mounted). If Turbo failed to intercept, the browser would have
    # navigated to the bare partial URL and unmounted everything.
    expect(page).to have_button("Add keyword")
  end
end
