import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    timeout: { type: Number, default: 5000 },
    type: String 
  }

  connect() {
    // Ensure this toast never comes back from Turbo's page cache
    this._beforeCache = () => {
      if (this.element && this.element.parentNode) {
        this.element.remove()
      }
    }
    document.addEventListener("turbo:before-cache", this._beforeCache)

    this.timeoutId = setTimeout(() => {
      this.dismiss()
    }, this.timeoutValue)
    
    // Add entrance animation
    this.element.style.transform = "translateX(100%)"
    this.element.style.opacity = "0"
    
    requestAnimationFrame(() => {
      this.element.style.transition = "all 0.3s ease-out"
      this.element.style.transform = "translateX(0)"
      this.element.style.opacity = "1"
    })
  }

  disconnect() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
    }
    if (this._beforeCache) {
      document.removeEventListener("turbo:before-cache", this._beforeCache)
    }
  }

  close() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
    }
    this.dismiss()
  }

  dismiss() {
    this.element.style.transition = "all 0.3s ease-in"
    this.element.style.transform = "translateX(100%)"
    this.element.style.opacity = "0"
    
    setTimeout(() => {
      if (this.element.parentNode) {
        this.element.remove()
      }
    }, 300)
  }

  // Pause auto-dismiss on hover
  mouseenter() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
    }
  }

  // Resume auto-dismiss on mouse leave
  mouseleave() {
    this.timeoutId = setTimeout(() => {
      this.dismiss()
    }, this.timeoutValue)
  }
}
