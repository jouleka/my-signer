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

  it "lists docs pages but no auth pages or underscore partials" do
    get sitemap_path(format: :xml)

    expect(response.body).to include("https://mysigner.dev/docs/quickstart/getting-started")
    expect(response.body).not_to include("/users/")
    expect(response.body).not_to include("_index")
    expect(response.body).to match(%r{<lastmod>\d{4}-\d{2}-\d{2}</lastmod>})
  end
end
