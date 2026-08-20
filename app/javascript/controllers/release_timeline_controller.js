import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["entry"]

  toggle(event) {
    const entry = event.currentTarget.closest("[data-release-timeline-target='entry']")
    if (!entry) return

    const detail = entry.querySelector("[data-timeline-detail]")
    const chevron = entry.querySelector("[data-timeline-chevron]")

    if (detail) {
      detail.classList.toggle("hidden")
    }

    if (chevron) {
      chevron.classList.toggle("rotate-90")
    }
  }
}
