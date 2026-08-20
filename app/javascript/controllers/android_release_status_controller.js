import { Controller } from "@hotwired/stimulus"

// Reveals staged-rollout fields only when the release status is `inProgress`.
// Mirrors the iOS release_type controller but for Android's status toggle —
// Google Play's userFraction is only valid when status=inProgress.
export default class extends Controller {
  static targets = ["radio", "rolloutFields", "fractionInput", "fractionPreview"]

  connect() {
    this.toggle()
    this.updatePreview()
  }

  toggle() {
    const selected = this.radioTargets.find(r => r.checked)?.value
    if (this.hasRolloutFieldsTarget) {
      this.rolloutFieldsTarget.classList.toggle("hidden", selected !== "inProgress")
    }
  }

  pickFraction(event) {
    event.preventDefault()
    const value = event.currentTarget.dataset.fraction
    if (!this.hasFractionInputTarget || !value) return
    this.fractionInputTarget.value = value
    this.updatePreview()
    this.fractionInputTarget.focus()
  }

  updatePreview() {
    if (!this.hasFractionPreviewTarget) return
    const raw = parseFloat(this.hasFractionInputTarget ? this.fractionInputTarget.value : "")
    if (isNaN(raw) || raw <= 0 || raw >= 1) {
      this.fractionPreviewTarget.textContent = "—"
      return
    }
    this.fractionPreviewTarget.textContent = `${(raw * 100).toFixed(raw < 0.01 ? 2 : raw < 0.1 ? 1 : 0)}%`
  }
}
