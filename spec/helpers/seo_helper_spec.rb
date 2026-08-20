# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeoHelper, type: :helper do
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
