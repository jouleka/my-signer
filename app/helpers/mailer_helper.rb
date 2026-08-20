# Editorial primitives for transactional email templates. Color tokens
# track the MySigner app dark theme exactly:
#
#   --color-base-100    oklch(14% 0.004 49.25)  ≈ #14110d   (body)
#   --color-base-200    oklch(21% 0.006 56)     ≈ #1f1a14   (card)
#   --color-base-300    oklch(26% 0.007 34)     ≈ #2a241d   (callout)
#   --color-base-content oklch(97% 0.001 106)   ≈ #f4ede0   (ink)
#   --color-primary     oklch(81% 0.111 293)    ≈ #c8a8f5   (lavender)
#   --color-primary-content                     ≈ #1a0f33   (text on lavender)
#   --color-success     oklch(70% 0.14 182)     ≈ #5dc299
#   --color-warning     oklch(79% 0.184 86)     ≈ #f0c073
#   --color-error       oklch(65% 0.241 354)    ≈ #f57c97
#
# All emails default to the dark scheme because the app is dark-first.
# Light-mode fallbacks live in `layouts/mailer.html.erb` under the
# `@media (prefers-color-scheme: light)` block — keep the two in sync.
module MailerHelper
  CTA_VARIANTS = {
    # Solid lavender filled — matches the auth-shell `.btn-primary-ms`
    # pill (background var(--color-primary), color var(--color-primary-content)).
    primary:   { bg: "#c8a8f5", border: "#c8a8f5", fg: "#1a0f33", class: "ms-cta-fill" },
    secondary: { bg: "transparent", border: "#3a342b", fg: "#f4ede0", class: "ms-cta-outline" },
    danger:    { bg: "#f57c97", border: "#f57c97", fg: "#1a0808", class: "ms-cta-danger" }
  }.freeze

  CALLOUT_VARIANTS = {
    neutral: { bg: "#1a1612", border: "#2c2820", text: "#f4ede0", strong: "#f4ede0", text_class: "ms-callout-neutral-text", class: "ms-callout-neutral" },
    success: { bg: "#102018", border: "#1e3a2c", text: "#5dc299", strong: "#7ed4ad", text_class: "ms-callout-success-text", class: "ms-callout-success" },
    warning: { bg: "#1f1810", border: "#3d2f17", text: "#f0c073", strong: "#f7d59b", text_class: "ms-callout-warning-text", class: "ms-callout-warning" },
    danger:  { bg: "#1f1314", border: "#3d2126", text: "#f57c97", strong: "#fa9eb1", text_class: "ms-callout-danger-text", class: "ms-callout-danger" },
    info:    { bg: "#13161f", border: "#2a3450", text: "#a8c0f5", strong: "#c1d3ff", text_class: "ms-callout-info-text", class: "ms-callout-info" }
  }.freeze

  # Editorial section marker. Mirrors the auth-shell's "№ 01 ─── LABEL"
  # row exactly — italic Instrument Serif numeral in primary lavender,
  # hairline rule, mono-uppercase label.
  def ms_eyebrow(number, label)
    label_text = label.to_s.upcase
    formatted_number = number.to_s.rjust(2, "0")
    raw <<~HTML
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 22px 0;">
        <tr>
          <td valign="middle" style="vertical-align:middle; padding-right:14px;">
            <span class="ms-primary" style="font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-style:italic; font-size:16px; line-height:1; color:#c8a8f5; letter-spacing:0;">№ #{formatted_number}</span>
          </td>
          <td valign="middle" width="40" class="ms-eyebrow-rule" height="1" style="width:40px; height:1px; line-height:1px; font-size:0; background-color:#3a342b;">&nbsp;</td>
          <td valign="middle" style="vertical-align:middle; padding-left:14px;">
            <span class="ms-faint" style="font-family:'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size:10px; letter-spacing:0.2em; color:#a8a094; text-transform:uppercase;">#{label_text}</span>
          </td>
        </tr>
      </table>
    HTML
  end

  # Display headline. `text_html` may include an `<em>...</em>` wrapping
  # the one word that should pop in primary lavender italic — same
  # treatment as the landing-page headlines ("Ship from your *terminal,*
  # not a tab.").
  def ms_headline(text_html, size: 36)
    raw <<~HTML
      <h1 class="ms-headline ms-ink" style="margin:0 0 18px 0; font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-weight:400; font-size:#{size}px; line-height:1.06; letter-spacing:-0.012em; color:#f4ede0;">
        #{text_html}
      </h1>
    HTML
  end

  def ms_lead(text_html, mute: true, margin_bottom: 24)
    color = mute ? "#cdc4b6" : "#f4ede0"
    klass = mute ? "ms-mute" : "ms-ink"
    raw <<~HTML
      <p class="#{klass}" style="margin:0 0 #{margin_bottom}px 0; font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-size:17px; line-height:1.55; color:#{color};">
        #{text_html}
      </p>
    HTML
  end

  def ms_body(text_html, margin_bottom: 16)
    raw <<~HTML
      <p class="ms-mute" style="margin:0 0 #{margin_bottom}px 0; font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-size:15.5px; line-height:1.62; color:#cdc4b6;">
        #{text_html}
      </p>
    HTML
  end

  def ms_fine_print(text_html, margin_bottom: 0, margin_top: 0)
    raw <<~HTML
      <p class="ms-faint" style="margin:#{margin_top}px 0 #{margin_bottom}px 0; font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-size:13.5px; font-style:italic; line-height:1.6; color:#8a8378;">
        #{text_html}
      </p>
    HTML
  end

  def ms_callout(content_html, variant: :neutral, accent_label: nil)
    style = CALLOUT_VARIANTS.fetch(variant)
    label_row = if accent_label
      safe_accent = ERB::Util.h(accent_label)
      <<~LABEL
        <tr>
          <td style="padding:14px 22px 0 22px;">
            <span class="#{style[:text_class]}" style="font-family:'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size:10px; letter-spacing:0.2em; text-transform:uppercase; color:#{style[:strong]}; font-weight:500;">
              #{safe_accent}
            </span>
          </td>
        </tr>
      LABEL
    else
      ""
    end
    raw <<~HTML
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="#{style[:class]}" style="background-color:#{style[:bg]}; border:1px solid #{style[:border]}; border-radius:6px; margin:0 0 24px 0;">
        #{label_row}
        <tr>
          <td style="padding:#{accent_label ? '8px 22px 16px 22px' : '16px 22px'};">
            <div class="#{style[:text_class]} ms-callout-text" style="font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-size:15.5px; line-height:1.55; color:#{style[:text]};">
              #{content_html}
            </div>
          </td>
        </tr>
      </table>
    HTML
  end

  # Bulletproof CTA with VML fallback for Outlook 2007–2019 (Word
  # rendering). Visually matches the app's `.btn-primary-ms` —
  # solid lavender pill with deep-violet text and a mono arrow.
  def ms_cta(label, url, variant: :primary, margin_top: 4, margin_bottom: 24)
    style = CTA_VARIANTS.fetch(variant)
    safe_label = ERB::Util.h(label)
    safe_url   = ERB::Util.h(url)
    raw <<~HTML
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" align="left" style="margin:#{margin_top}px 0 #{margin_bottom}px 0;">
        <tr>
          <td align="center" valign="middle" class="ms-cta-cell #{style[:class]}" bgcolor="#{style[:bg]}" style="background-color:#{style[:bg]}; border:1px solid #{style[:border]}; border-radius:6px;">
            <!--[if mso]>
            <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="#{safe_url}" style="height:46px; v-text-anchor:middle; width:240px;" arcsize="13%" stroke="f" fillcolor="#{style[:bg]}">
              <w:anchorlock/>
              <center style="color:#{style[:fg]}; font-family:Georgia, 'Times New Roman', serif; font-size:14px; font-weight:600; letter-spacing:0.005em;">#{safe_label}</center>
            </v:roundrect>
            <![endif]-->
            <!--[if !mso]><!-->
            <a href="#{safe_url}" target="_blank" rel="noopener" style="display:inline-block; padding:14px 26px; font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-size:15.5px; font-weight:400; line-height:1; color:#{style[:fg]}; text-decoration:none; border-radius:6px; letter-spacing:0.005em;">
              #{safe_label}&nbsp;<span style="font-family:'JetBrains Mono', ui-monospace, monospace; font-size:13px; letter-spacing:-0.02em;">&rarr;</span>
            </a>
            <!--<![endif]-->
          </td>
        </tr>
      </table>
    HTML
  end

  # Mono pill — same shape used in the app for kbd-mono / token bits.
  #
  # SECURITY: `content` is escaped (`ERB::Util.h` passes html_safe strings
  # through unchanged). Devise's default `email_regexp`
  # (`/\A[^@\s]+@[^@\s]+\z/`) accepts `<`, `>`, `"`, `&`, so a payload like
  # `"a<svg/onload=...>@b.com"` would otherwise validate at signup, persist
  # to the User row, and render as live HTML in any Devise mailer that
  # interpolates `@resource.email` here — including the
  # `email_changed.html.erb` notice that's sent to the *previous* address
  # (i.e. attacker-authored HTML reaches the original mailbox owner).
  def ms_meta_pill(content)
    safe_content = ERB::Util.h(content)
    raw <<~HTML
      <span class="ms-mono ms-meta-pill" style="display:inline-block; padding:3px 9px; background-color:rgba(244,237,224,0.06); border:1px solid rgba(244,237,224,0.14); border-radius:3px; font-family:'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size:12.5px; line-height:1.4; color:#f4ede0;">#{safe_content}</span>
    HTML
  end

  # Larger mono "token block" — for surfaces of secrets, truncated
  # URLs, error messages.
  def ms_token_block(content_html, mono: true)
    family = mono ? "'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, Consolas, monospace" : "'Instrument Serif', Georgia, 'Times New Roman', serif"
    raw <<~HTML
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 22px 0;">
        <tr>
          <td class="ms-token-block ms-mono" style="padding:14px 18px; background-color:#14110d; border:1px solid #2c2820; border-radius:6px; font-family:#{family}; font-size:12.5px; line-height:1.55; color:#f4ede0; word-break:break-all;">
            #{content_html}
          </td>
        </tr>
      </table>
    HTML
  end

  # Hairline rule. Quieter than `<hr>`, which Outlook renders inconsistently.
  def ms_rule(margin_top: 26, margin_bottom: 26, width: "100%")
    raw <<~HTML
      <table role="presentation" class="ms-rule-hr" cellpadding="0" cellspacing="0" border="0" style="width:#{width}; margin:#{margin_top}px 0 #{margin_bottom}px 0;">
        <tr>
          <td class="ms-rule" height="1" style="height:1px; line-height:1px; font-size:0; background-color:#2c2820;">&nbsp;</td>
        </tr>
      </table>
    HTML
  end

  # Editorial labelled key/value rows. Used for "From: ..." / "Role:
  # ..." style metadata blocks where a flat callout would be too heavy.
  #
  # `label` is plain text and is always escaped. `value_html` is treated
  # as HTML; callers passing user-controlled data must wrap it in either
  # an escaping helper (`ms_meta_pill`, etc.) or `ERB::Util.h(...).html_safe`
  # — the existing call sites already follow that convention.
  def ms_meta_row(label, value_html)
    safe_label = ERB::Util.h(label)
    raw <<~HTML
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 8px 0;">
        <tr>
          <td valign="top" width="120" class="ms-faint" style="width:120px; vertical-align:top; padding-right:18px; font-family:'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size:10px; letter-spacing:0.2em; text-transform:uppercase; color:#8a8378; padding-top:5px;">
            #{safe_label}
          </td>
          <td valign="top" class="ms-ink" style="vertical-align:top; font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-size:16px; line-height:1.5; color:#f4ede0;">
            #{value_html}
          </td>
        </tr>
      </table>
    HTML
  end

  # Inline REVOKED-style stamp for revocation / expiration emails.
  def ms_stamp(label = "REVOKED")
    raw <<~HTML
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" align="left" style="margin:0 0 22px 0;">
        <tr>
          <td class="ms-callout-danger-text" style="padding:5px 12px; border:1.5px solid #f57c97; border-radius:3px; font-family:'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, Consolas, monospace; font-size:11px; letter-spacing:0.24em; text-transform:uppercase; color:#f57c97; font-weight:500;">
            #{ERB::Util.h(label)}
          </td>
        </tr>
      </table>
    HTML
  end

  # Inline link. Both `label` and `url` are escaped so an attacker-
  # controlled value (e.g. the contact form's `@email`, which has no
  # server-side validation beyond `present?`) cannot break out of the
  # `href` attribute or inject HTML into the visible label. URL-scheme
  # safety (e.g. blocking `javascript:`) is the caller's responsibility;
  # the only callers today either use Rails-generated URLs (`*_url`
  # helpers) or `mailto:#{user_email}`, neither of which exposes a
  # scheme-injection surface once attribute-quote breakouts are closed.
  def ms_link(label, url)
    safe_label = ERB::Util.h(label)
    safe_url   = ERB::Util.h(url)
    raw <<~HTML
      <a href="#{safe_url}" class="ms-link" style="color:#c8a8f5; text-decoration:underline; text-underline-offset:3px; text-decoration-color:rgba(200,168,245,0.45);">#{safe_label}</a>
    HTML
  end

  # Display-style number — used for trial countdown, days remaining
  # headlines. Big italic Instrument Serif numeral in primary lavender,
  # mirroring the editorial display sizes on the auth-shell.
  def ms_display_num(num, suffix_html = "days")
    raw <<~HTML
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 4px 0;">
        <tr>
          <td valign="bottom" class="ms-display-num" style="vertical-align:bottom; padding-right:14px; font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-style:italic; font-size:80px; line-height:0.9; color:#c8a8f5; letter-spacing:-0.03em;">#{num}</td>
          <td valign="bottom" style="vertical-align:bottom; padding-bottom:12px;">
            <span class="ms-mute" style="font-family:'Instrument Serif', Georgia, 'Times New Roman', serif; font-size:16px; line-height:1; color:#a8a094; font-style:italic;">#{suffix_html}</span>
          </td>
        </tr>
      </table>
    HTML
  end
end
