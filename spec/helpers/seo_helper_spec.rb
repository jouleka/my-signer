# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeoHelper, type: :helper do
  describe "#page_title / #meta_description" do
    it "unescapes content_for SafeBuffers so ERB escapes them only once" do
      captured = helper.capture { "Ship iOS & Android" }

      expect(helper.page_title(captured)).to eq("Ship iOS & Android | MySigner")
      expect(helper.meta_description(captured)).to eq("Ship iOS & Android")
    end

    it "falls back to defaults when blank" do
      expect(helper.page_title(nil)).to include("MySigner")
      expect(helper.meta_description("")).to eq(SeoHelper::DEFAULT_DESCRIPTION)
    end
  end

  describe "#canonical_url" do
    it "always uses the apex host and strips trailing slashes" do
      expect(helper.canonical_url("/docs/")).to eq("https://mysigner.dev/docs")
      expect(helper.canonical_url("/")).to eq("https://mysigner.dev/")
    end
  end

  describe "JSON-LD <script> escaping" do
    it "escapes a </script> breakout attempt in breadcrumb names" do
      html = helper.breadcrumb_json_ld([ { name: "</script><script>alert(1)</script>", url: "/x" } ])

      expect(html).not_to include("</script><script>")
      # The forward slash of the closing tag is unicode-escaped by json_escape.
      expect(html).to include('</script')
    end

    it "escapes < and > in faq content" do
      html = helper.faq_json_ld([ { question: "a</script>", answer: "b</script>" } ])

      expect(html.scan("</script>").length).to eq(1) # only the real closing tag
    end

    it "still produces valid, parseable JSON for normal data" do
      html = helper.tech_article_json_ld(
        title: "Hello", description: "World", url: "/docs/x", category: "Guides"
      )
      json = html[/<script[^>]*>(.*)<\/script>/m, 1]

      expect { JSON.parse(json) }.not_to raise_error
      expect(JSON.parse(json)["headline"]).to eq("Hello")
    end
  end
end
