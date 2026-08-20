import { Controller } from "@hotwired/stimulus"

// Handles keyword chip add/remove for Custom Product Pages.
// Uses standard form submission via Turbo (no fetch calls needed since
// the controller actions handle redirects with flash messages).
export default class extends Controller {
  static values = {
    addUrl: String,
    removeUrl: String
  }

  static targets = ["keywordInput", "chipContainer"]

  addKeyword(event) {
    event.preventDefault()
    const input = this.keywordInputTarget
    const keyword = input.value.trim()
    if (!keyword) return
    input.value = ""
  }

  removeKeyword(event) {
    event.preventDefault()
    const chip = event.currentTarget.closest("[data-keyword-id]")
    if (chip) {
      chip.classList.add("opacity-50", "pointer-events-none")
    }
  }
}
