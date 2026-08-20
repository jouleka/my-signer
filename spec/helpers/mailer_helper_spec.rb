require "rails_helper"

# Regression coverage for the mailer_helper escape boundaries.
#
# These helpers are interpolated inside `raw <<~HTML` blocks, so any
# unescaped substring lands in the rendered email as live HTML. The
# inputs that flow into them through transactional templates include
# user-controlled values whose only validation upstream is permissive
# (Devise's default `email_regexp` accepts `<`, `>`, `"`, `&`; the
# contact form does no email validation at all). The escape MUST happen
# at the helper boundary — not at the call site — so future templates
# can call these helpers without re-deriving the threat model.
RSpec.describe MailerHelper, type: :helper do
  HOSTILE = %q{</a><svg/onload=alert(1)>"@b.com}.freeze

  describe "#ms_meta_pill" do
    it "escapes user-controlled content" do
      out = helper.ms_meta_pill(HOSTILE)
      expect(out).not_to include("<svg/onload")
      expect(out).not_to include("</a><svg")
      expect(out).to include(ERB::Util.h(HOSTILE))
    end

    it "lets html_safe content through unchanged" do
      out = helper.ms_meta_pill('<em class="pill">label</em>'.html_safe)
      expect(out).to include('<em class="pill">label</em>')
    end
  end

  describe "#ms_link" do
    it "escapes the label" do
      out = helper.ms_link(HOSTILE, "https://example.com/")
      expect(out).not_to include("<svg/onload")
      expect(out).to include(ERB::Util.h(HOSTILE))
    end

    it "escapes the URL so an attacker cannot break out of the href attribute" do
      hostile_url = %q{https://example.com/" onclick="alert(1)}
      out = helper.ms_link("Click", hostile_url)
      # The `"` that would close the href must be encoded.
      expect(out).not_to match(/href="https:\/\/example\.com\/" onclick=/)
      expect(out).to include(ERB::Util.h(hostile_url))
    end
  end

  describe "#ms_meta_row" do
    it "escapes the label (label is treated as plain text)" do
      out = helper.ms_meta_row(HOSTILE, "value".html_safe)
      expect(out).not_to include("<svg/onload")
      expect(out).to include(ERB::Util.h(HOSTILE))
    end

    it "passes html_safe value_html through unchanged" do
      value = '<span class="ms-ink">2026-05-06</span>'.html_safe
      out = helper.ms_meta_row("Date", value)
      expect(out).to include(value)
    end
  end

  describe "#ms_cta" do
    it "escapes the URL so an attacker cannot break out of the href attribute" do
      hostile_url = %q{https://example.com/" onclick="alert(1)}
      out = helper.ms_cta("Click", hostile_url)
      expect(out).not_to match(/href="https:\/\/example\.com\/" onclick=/)
      expect(out).to include(ERB::Util.h(hostile_url))
    end
  end

  describe "#ms_callout" do
    it "escapes the accent_label" do
      out = helper.ms_callout("body".html_safe, accent_label: HOSTILE)
      expect(out).not_to include("<svg/onload")
      expect(out).to include(ERB::Util.h(HOSTILE))
    end
  end
end
