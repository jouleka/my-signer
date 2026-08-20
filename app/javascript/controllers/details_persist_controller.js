import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    key: String
  }

  connect() {
    this.restoreState()
    this.bindTurboEvents()
  }

  disconnect() {
    this.unbindTurboEvents()
  }

  bindTurboEvents() {
    this.turboBeforeRender = this.turboBeforeRender.bind(this)
    document.addEventListener("turbo:before-render", this.turboBeforeRender)
  }

  unbindTurboEvents() {
    document.removeEventListener("turbo:before-render", this.turboBeforeRender)
  }

  turboBeforeRender() {
    // Save state before Turbo renders new content
    const isOpen = this.element.open
    const key = this.getStorageKey()
    if (isOpen) {
      sessionStorage.setItem(key, "true")
    }
  }

  restoreState() {
    const key = this.getStorageKey()
    const savedState = sessionStorage.getItem(key)
    if (savedState === "true") {
      // Use multiple attempts to ensure DOM is ready
      let attempts = 0
      const tryRestore = () => {
        attempts++
        if (document.contains(this.element)) {
          this.element.open = true
          // Clear the stored state after restoring
          sessionStorage.removeItem(key)
        } else if (attempts < 10) {
          // Retry up to 10 times
          setTimeout(tryRestore, 50)
        }
      }
      requestAnimationFrame(() => {
        setTimeout(tryRestore, 0)
      })
    }
  }

  getStorageKey() {
    // Use a unique key based on the details element's context
    // Try to find a unique identifier (like a form action or page path)
    const form = this.element.closest("form")
    const formAction = form?.action || window.location.pathname
    const detailsId = this.element.id || this.elementIndex()
    return `details_open_${formAction}_${detailsId}`
  }

  elementIndex() {
    // Get index of this details element among siblings
    const siblings = Array.from(this.element.parentElement?.children || [])
    const detailsElements = siblings.filter(el => el.tagName === "DETAILS")
    return detailsElements.indexOf(this.element)
  }
}

