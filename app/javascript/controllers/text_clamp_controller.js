import { Controller } from "@hotwired/stimulus"

/**
 * Clamps multiline text with a "Show more" / "Show less" toggle.
 * Wraps the target element with a max-height and fade-out gradient.
 *
 * Usage:
 *   <div data-controller="text-clamp" data-text-clamp-max-value="160">
 *     Long text here...
 *   </div>
 */
export default class extends Controller {
  static values = { max: { type: Number, default: 160 } }

  connect() {
    // Wait a frame so the element has its rendered height
    requestAnimationFrame(() => this._setup())
  }

  _setup() {
    const el = this.element
    const natural = el.scrollHeight
    const max = this.maxValue

    // Only clamp if content actually exceeds the max height
    if (natural <= max) {
      el.style.maxHeight = "none"
      return
    }

    this._clamped = true
    el.style.maxHeight = `${max}px`
    el.style.overflow = "hidden"

    // Fade gradient overlay
    const fade = document.createElement("div")
    fade.className = "absolute bottom-0 left-0 right-0 h-12 bg-gradient-to-b from-transparent to-[var(--color-base-100)] pointer-events-none transition-opacity duration-200"
    el.style.position = "relative"
    el.appendChild(fade)
    this._fade = fade

    // Toggle button
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "inline-block mt-1.5 text-xs font-medium text-primary cursor-pointer bg-transparent border-0 p-0 transition-colors duration-150 hover:text-primary/70"
    btn.textContent = "Show more"
    btn.addEventListener("click", () => this._toggle(natural))
    el.parentNode.insertBefore(btn, el.nextSibling)
    this._btn = btn
  }

  _toggle(natural) {
    const el = this.element
    if (this._clamped) {
      el.style.maxHeight = `${natural}px`
      el.style.overflow = "visible"
      this._fade.style.opacity = "0"
      this._btn.textContent = "Show less"
      this._clamped = false
    } else {
      el.style.maxHeight = `${this.maxValue}px`
      el.style.overflow = "hidden"
      this._fade.style.opacity = "1"
      this._btn.textContent = "Show more"
      this._clamped = true
    }
  }

  disconnect() {
    this._btn?.remove()
    this._fade?.remove()
  }
}
