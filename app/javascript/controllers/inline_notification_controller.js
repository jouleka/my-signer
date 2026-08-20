import { Controller } from "@hotwired/stimulus"

/**
 * Inline notification with optional auto-dismiss and smooth animations.
 *
 * Usage:
 *   <div data-controller="inline-notification"
 *        data-inline-notification-timeout-value="5000"
 *        data-inline-notification-dismissable-value="true">
 *     ...content...
 *     <button data-action="click->inline-notification#dismiss">X</button>
 *   </div>
 *
 * Values:
 *   timeout:     ms before auto-dismiss (0 = never, default 0)
 *   dismissable: show close button support (default true)
 */
export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 0 },
    dismissable: { type: Boolean, default: true }
  }

  connect() {
    // Entrance animation
    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(-8px)"
    this.element.style.maxHeight = "0"
    this.element.style.overflow = "hidden"

    requestAnimationFrame(() => {
      // Measure natural height
      this.element.style.maxHeight = "none"
      const height = this.element.scrollHeight
      this.element.style.maxHeight = "0"

      // Force reflow
      void this.element.offsetHeight

      this.element.style.transition = "all 0.35s cubic-bezier(0.16, 1, 0.3, 1)"
      this.element.style.opacity = "1"
      this.element.style.transform = "translateY(0)"
      this.element.style.maxHeight = height + "px"

      // After animation, remove max-height constraint
      setTimeout(() => {
        if (this.element) {
          this.element.style.maxHeight = "none"
          this.element.style.overflow = "visible"
        }
      }, 350)
    })

    // Start auto-dismiss countdown
    if (this.timeoutValue > 0) {
      this._startCountdown()
    }

    // Turbo cache cleanup
    this._beforeCache = () => this.element?.remove()
    document.addEventListener("turbo:before-cache", this._beforeCache)
  }

  disconnect() {
    this._clearTimers()
    if (this._beforeCache) {
      document.removeEventListener("turbo:before-cache", this._beforeCache)
    }
  }

  dismiss() {
    this._clearTimers()

    const height = this.element.scrollHeight
    this.element.style.maxHeight = height + "px"
    this.element.style.overflow = "hidden"

    // Force reflow
    void this.element.offsetHeight

    this.element.style.transition = "all 0.3s cubic-bezier(0.4, 0, 0.2, 1)"
    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(-8px)"
    this.element.style.maxHeight = "0"
    this.element.style.marginTop = "0"
    this.element.style.marginBottom = "0"
    this.element.style.paddingTop = "0"
    this.element.style.paddingBottom = "0"

    setTimeout(() => this.element?.remove(), 300)
  }

  // Pause auto-dismiss on hover
  pause() {
    if (this._timer) {
      clearTimeout(this._timer)
      this._timer = null
    }
    // Pause progress bar
    const bar = this.element.querySelector("[data-progress-bar]")
    if (bar) bar.style.animationPlayState = "paused"
  }

  // Resume auto-dismiss on mouse leave
  resume() {
    if (this.timeoutValue > 0 && !this._dismissed) {
      const remaining = this._remaining || this.timeoutValue
      this._timer = setTimeout(() => this.dismiss(), remaining)
      const bar = this.element.querySelector("[data-progress-bar]")
      if (bar) bar.style.animationPlayState = "running"
    }
  }

  _startCountdown() {
    this._dismissed = false
    this._remaining = this.timeoutValue
    this._startedAt = Date.now()

    this._timer = setTimeout(() => {
      this._dismissed = true
      this.dismiss()
    }, this.timeoutValue)
  }

  _clearTimers() {
    if (this._timer) {
      // Track remaining time for pause/resume
      if (this._startedAt) {
        this._remaining = Math.max(0, this.timeoutValue - (Date.now() - this._startedAt))
      }
      clearTimeout(this._timer)
      this._timer = null
    }
  }
}
