import { Controller } from "@hotwired/stimulus"

const HINTS = [
  {
    key: "emoji",
    label: "Use Emojis",
    pattern: /[\u{1F300}-\u{1F9FF}]/u,
    present: true,
    description: "Emojis help your release notes stand out in the Play Store feed.",
    example: "NEW: Dark mode is here! \u{1F30D}"
  },
  {
    key: "short",
    label: "Keep It Short",
    maxLength: 300,
    description: "Google Play shows ~300 characters before truncating. Front-load key info.",
    example: "Lead with the most important changes first."
  },
  {
    key: "keywords",
    label: "Include Keywords",
    description: "Mention your core features in release notes to improve discoverability.",
    example: "Improved offline sync, faster photo editing."
  },
  {
    key: "user_benefit",
    label: "Focus on Benefits",
    pattern: /faster|easier|better|improved|now you can|enjoy/i,
    present: true,
    description: "Frame changes as user benefits, not technical fixes.",
    example: "Photos now load 3x faster" vs "Optimized image cache"
  }
]

export default class extends Controller {
  static targets = ["hintsPanel", "hintCards"]
  static values = { platform: String }

  connect() {
    if (this.platformValue !== "android") {
      this._hidePanel()
    }
  }

  analyze(event) {
    if (this.platformValue !== "android") {
      this._hidePanel()
      return
    }

    this._showPanel()
    const text = event?.target?.value || this._getRenderedText() || ""
    this._evaluateHints(text)
  }

  _evaluateHints(text) {
    if (!this.hasHintCardsTarget) return

    const cards = this.hintCardsTarget.querySelectorAll("[data-hint-key]")
    cards.forEach(card => {
      const key = card.dataset.hintKey
      const hint = HINTS.find(h => h.key === key)
      if (!hint) return

      let pass = false

      if (hint.pattern) {
        const matches = hint.pattern.test(text)
        pass = hint.present ? matches : !matches
      } else if (hint.maxLength) {
        pass = text.length <= hint.maxLength
      } else {
        // No auto-check; always show as suggestion
        pass = false
      }

      // Set border color directly for the dynamic per-state colors
      // (simpler than toggling Tailwind arbitrary-value classes that don't get scanned)
      if (pass) {
        card.style.borderColor = "oklch(var(--color-cat-new) / 0.2)"
      } else {
        card.style.borderColor = "oklch(var(--color-cat-fixed) / 0.2)"
      }
    })
  }

  _getRenderedText() {
    const input = this.element.closest("[data-controller*='release-note-editor']")
      ?.querySelector("[data-release-note-editor-target='renderedTextInput']")
    return input?.value || ""
  }

  _showPanel() {
    if (this.hasHintsPanelTarget) {
      this.hintsPanelTarget.classList.remove("hidden")
    }
  }

  _hidePanel() {
    if (this.hasHintsPanelTarget) {
      this.hintsPanelTarget.classList.add("hidden")
    }
  }
}
