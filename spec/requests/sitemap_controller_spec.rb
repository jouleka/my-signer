require "rails_helper"

RSpec.describe "SitemapController", type: :request do
  it "includes the public pricing and legal pages" do
    get sitemap_path(format: :xml)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml")
    expect(response.body).to include("https://mysigner.dev/pricing")
    expect(response.body).to include("https://mysigner.dev/terms-and-conditions")
    expect(response.body).to include("https://mysigner.dev/privacy-policy")
    expect(response.body).to include("https://mysigner.dev/refund-policy")
  end
end
