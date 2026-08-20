import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "count", "display", "bar", "track"]
  static values = { limit: Number }

  connect() {
    this.update()
  }

  update() {
    if (!this.hasInputTarget || !this.hasCountTarget) return

    const length = this.inputTarget.value.length
    const limit = this.limitValue

    this.countTarget.textContent = length

    if (limit > 0) {
      const pct = Math.min((length / limit) * 100, 100)
      const isWarn = length > limit * 0.9 && length <= limit
      const isOver = length > limit

      // Update progress bar
      if (this.hasBarTarget) {
        this.barTarget.style.width = `${pct}%`
        // Reset all variants then apply current
        this.barTarget.classList.remove("bg-warning/60", "bg-error/70", "bg-primary/35")
        if (isOver) {
          this.barTarget.classList.add("bg-error/70")
        } else if (isWarn) {
          this.barTarget.classList.add("bg-warning/60")
        } else {
          this.barTarget.classList.add("bg-primary/35")
        }
      }

      // Update counter badge
      if (this.hasDisplayTarget) {
        this.displayTarget.classList.remove(
          "bg-warning/10", "text-warning/80",
          "bg-error/[0.12]", "text-error/90", "font-bold",
          "bg-base-content/[0.04]", "text-base-content/30"
        )
        if (isOver) {
          this.displayTarget.classList.add("bg-error/[0.12]", "text-error/90", "font-bold")
        } else if (isWarn) {
          this.displayTarget.classList.add("bg-warning/10", "text-warning/80")
        } else {
          this.displayTarget.classList.add("bg-base-content/[0.04]", "text-base-content/30")
        }
      }

      // Update input border
      if (isOver) {
        this.inputTarget.classList.add("border-error/40", "shadow-[0_0_0_3px_oklch(var(--color-error)/0.08)]")
      } else {
        this.inputTarget.classList.remove("border-error/40", "shadow-[0_0_0_3px_oklch(var(--color-error)/0.08)]")
      }
    }
  }
}
