import { Controller } from "@hotwired/stimulus"

// Dismissable controller — hides an element and remembers it via localStorage
//
// Usage:
//   <div data-controller="dismissable" data-dismissable-key-value="my-callout">
//     <button data-action="click->dismissable#dismiss">×</button>
//   </div>

export default class extends Controller {
  static values = {
    key: String // localStorage key, e.g. "feature-callout"
  }

  connect() {
    if (this.isDismissed()) {
      this.element.remove()
    }
  }

  dismiss() {
    localStorage.setItem(this.storageKey, Date.now().toString())
    this.element.style.transition = "opacity 200ms ease, max-height 200ms ease"
    this.element.style.opacity = "0"
    this.element.style.maxHeight = this.element.offsetHeight + "px"
    requestAnimationFrame(() => {
      this.element.style.maxHeight = "0"
      this.element.style.marginBottom = "0"
      this.element.style.paddingTop = "0"
      this.element.style.paddingBottom = "0"
      this.element.style.overflow = "hidden"
    })
    setTimeout(() => this.element.remove(), 250)
  }

  isDismissed() {
    return localStorage.getItem(this.storageKey) !== null
  }

  get storageKey() {
    return `dismissed:${this.keyValue}`
  }
}
