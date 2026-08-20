import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String, sourceId: String }
  static targets = ["source"]

  async copy(event) {
    event.preventDefault()
    const source = event.currentTarget
    // Try multiple ways to get the text to copy
    let text = this.textValue
    if (!text && this.hasSourceTarget) {
      text = this.sourceTarget.textContent
    }
    if (!text && this.hasSourceIdValue) {
      const el = document.getElementById(this.sourceIdValue)
      text = el?.textContent
    }
    if (!text) {
      text = source?.dataset?.copyTextValue || this.element?.dataset?.copyTextValue
    }
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
      this._showFeedback(source, true)
      this._flash("Copied")
    } catch (_) {
      this._showFeedback(source, false)
      this._flash("Copy failed")
    }
  }

  _showFeedback(button, success) {
    const icon = button?.querySelector("i")
    if (!icon) return
    const originalClass = icon.className
    icon.className = success
      ? "fa-solid fa-check text-xs text-success"
      : "fa-solid fa-xmark text-xs text-error"
    setTimeout(() => {
      icon.className = originalClass
    }, 2000)
  }

  _flash(message) {
    const container = document.getElementById("toast-container")
    if (!container) return
    const div = document.createElement("div")
    div.className = "alert alert-success shadow-lg max-w-sm"
    div.innerHTML = `<i class="fa-solid fa-circle-check"></i><span class="flex-1">${message}</span>`
    container.appendChild(div)
    setTimeout(() => div.remove(), 1200)
  }
}


