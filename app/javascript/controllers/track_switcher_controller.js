import { Controller } from "@hotwired/stimulus"

// Pipeline section track-switcher pill group. Each pill carries a
// `data-track="testflight"` attribute; clicking one shifts the active
// state and updates any [data-track-switcher-target="label"] nodes to
// the new track name (used inside the inline `$ mysigner ship <track>`
// snippet). Inline styles match the rest of the marketing surface so
// daisyUI primary tokens flow through without an extra CSS class.
export default class extends Controller {
  static targets = ["pill", "label"]

  select(event) {
    const track = event.currentTarget.dataset.track
    if (!track) return
    this._activate(track)
  }

  connect() {
    const initial = this.element.dataset.initialTrack ||
      this.pillTargets.find(p => p.dataset.initial)?.dataset.track ||
      this.pillTargets[0]?.dataset.track
    if (initial) this._activate(initial)
  }

  _activate(track) {
    this.pillTargets.forEach(p => {
      const isActive = p.dataset.track === track
      if (isActive) {
        p.style.background = "var(--color-primary)"
        p.style.color = "var(--color-primary-content)"
        p.style.borderColor = "var(--color-primary)"
      } else {
        p.style.background = ""
        p.style.color = ""
        p.style.borderColor = ""
      }
      p.setAttribute("aria-pressed", isActive ? "true" : "false")
    })
    this.labelTargets.forEach(t => { t.textContent = track })
  }
}
