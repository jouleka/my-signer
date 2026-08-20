import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "counter", "templateSelect", "submitBtn"]
  static values = {
    maxLength: { type: Number, default: 350 },
    templates: Array
  }

  connect() {
    this.updateCounter()
  }

  updateCounter() {
    if (!this.hasTextareaTarget || !this.hasCounterTarget) return

    const len = this.textareaTarget.value.length
    const max = this.maxLengthValue
    const remaining = max - len

    this.counterTarget.textContent = `${len}/${max}`

    // Style based on remaining
    this.counterTarget.classList.remove("text-error", "text-warning", "text-base-content/40")
    if (remaining < 0) {
      this.counterTarget.classList.add("text-error")
    } else if (remaining < 50) {
      this.counterTarget.classList.add("text-warning")
    } else {
      this.counterTarget.classList.add("text-base-content/40")
    }

    // Disable submit if over limit or empty
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = len === 0 || len > max
    }
  }

  selectTemplate(event) {
    if (!this.hasTextareaTarget) return

    const select = event.target
    const body = select.value
    if (body) {
      this.textareaTarget.value = body
      this.updateCounter()
      select.selectedIndex = 0
    }
  }

  input() {
    this.updateCounter()
  }
}
