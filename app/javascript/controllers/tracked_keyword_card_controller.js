import { Controller } from "@hotwired/stimulus"

// Rotates the chevron and hides/shows the detail Turbo Frame when the
// header link is clicked. On first expand, Turbo fetches the detail partial
// into the frame; on subsequent toggles, we just hide/show the populated
// frame without re-fetching.
export default class extends Controller {
  static targets = ["chevron", "detailFrame"]

  connect() {
    if (this.hasDetailFrameTarget) {
      this.detailFrameTarget.hidden = true
    }
  }

  toggle(event) {
    const frameHasContent = this.hasDetailFrameTarget &&
                            this.detailFrameTarget.children.length > 0

    // Let Turbo fetch only on the first expand. After that, we just toggle
    // visibility — no need to re-hit the server.
    if (frameHasContent) {
      event.preventDefault()
    }

    const expanded = this.element.classList.toggle("is-expanded")

    if (this.hasChevronTarget) {
      this.chevronTarget.classList.toggle("rotate-90")
    }

    if (this.hasDetailFrameTarget) {
      this.detailFrameTarget.hidden = !expanded
    }
  }
}
