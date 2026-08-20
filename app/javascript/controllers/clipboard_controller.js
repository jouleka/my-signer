import { Controller } from "@hotwired/stimulus"

// Clipboard copy controller for code blocks
export default class extends Controller {
  static values = { content: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.contentValue)
      this.showSuccess()
    } catch (err) {
      console.error("Failed to copy:", err)
      this.showError()
    }
  }

  showSuccess() {
    const icon = this.element.querySelector("i")
    if (icon) {
      const originalClass = icon.className
      icon.className = "fa-solid fa-check text-success"
      setTimeout(() => {
        icon.className = originalClass
      }, 2000)
    }
  }

  showError() {
    const icon = this.element.querySelector("i")
    if (icon) {
      const originalClass = icon.className
      icon.className = "fa-solid fa-xmark text-error"
      setTimeout(() => {
        icon.className = originalClass
      }, 2000)
    }
  }
}
