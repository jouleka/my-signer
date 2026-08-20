import { Controller } from "@hotwired/stimulus"

// Copies the once-shown API token to the clipboard. Replaces a former
// inline onclick attribute that was getting blocked by the production
// CSP (script-src has 'strict-dynamic' + nonce, no 'unsafe-inline').
//
// The source span's id stays as `onboarding-plain-token` so the existing
// markup keeps working; we just point this controller at it via
// `data-onboarding-token-copy-source-id-value`.
export default class extends Controller {
  static values = {
    sourceId: String,
    confirmText: { type: String, default: "Copied" },
    confirmDurationMs: { type: Number, default: 1400 }
  }

  async copy(event) {
    event.preventDefault()

    const source = document.getElementById(this.sourceIdValue)
    const text = source?.textContent?.trim()
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
    } catch (_) {
      // Older browsers / hardened webviews — silently no-op rather
      // than crash the flow. The token text is already on screen for
      // manual selection.
      return
    }

    const button = event.currentTarget
    const previousText = button.innerText
    button.innerText = this.confirmTextValue
    setTimeout(() => { button.innerText = previousText }, this.confirmDurationMs)
  }
}
