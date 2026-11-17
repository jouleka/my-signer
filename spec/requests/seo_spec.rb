# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SEO metadata", type: :request do
  def json_ld_blocks(body)
    body.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).map { |(json)| JSON.parse(json) }
  end

  describe "landing page" do
    before { get "/" }

    it "escapes the ampersand in the title exactly once" do
      expect(response.body).to include("<title>Ship iOS &amp; Android Apps from Your Terminal | MySigner</title>")
      expect(response.body).not_to include("&amp;amp;")
    end

    it "is indexable and has an apex canonical" do
      expect(response.body).not_to include('name="robots"')
      expect(response.body).to include('<link rel="canonical" href="https://mysigner.dev/">')
    end

    it "emits well-formed Organization, WebSite and SoftwareApplication JSON-LD" do
      blocks = json_ld_blocks(response.body)
      expect(blocks.map { |b| b["@type"] }).to contain_exactly("Organization", "WebSite", "SoftwareApplication")

      app = blocks.find { |b| b["@type"] == "SoftwareApplication" }
      expect(app["applicationCategory"]).to eq("DeveloperApplication")
      expect(app["description"]).to include("iOS & Android")
      prices = app["offers"].map { |o| o["price"] }
      expect(prices).to include("0", "12.00", "96.00", "49.00", "390.00")
    end
  end

  describe "pricing page" do
    it "emits FAQPage JSON-LD that matches the visible FAQ" do
      get pricing_path

      faq = json_ld_blocks(response.body).find { |b| b["@type"] == "FAQPage" }
      expect(faq["mainEntity"].size).to eq(PricingHelper::PRICING_FAQS.size)
      expect(response.body).to include(CGI.escapeHTML(PricingHelper::PRICING_FAQS.first[:q]))
    end
  end

  describe "docs pages" do
    it "uses a single-escaped, non-duplicated title and valid JSON-LD" do
      get "/docs/quickstart/getting-started"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<title>Getting Started — Quickstart | MySigner</title>")
      expect(response.body).to include('<link rel="canonical" href="https://mysigner.dev/docs/quickstart/getting-started">')
      expect(json_ld_blocks(response.body).map { |b| b["@type"] }).to contain_exactly("BreadcrumbList", "TechArticle")
    end

    it "does not serve underscore partials as pages" do
      get "/docs/commands/_index"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "auth pages" do
    it "marks the sign-in page noindex" do
      get new_user_session_path

      expect(response.body).to include('<meta name="robots" content="noindex">')
    end

    it "marks the sign-up page noindex" do
      get new_user_registration_path

      expect(response.body).to include('<meta name="robots" content="noindex">')
    end
  end
end
