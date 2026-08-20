import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "progressBar", "progressText", "submitGate"]
  static values = { total: Number }

  toggle(event) {
    const checkbox = event.currentTarget
    const key = checkbox.dataset.releaseChecklistKeyParam
    const checked = checkbox.checked
    const url = checkbox.dataset.releaseChecklistUrlParam

    if (!key || !url) return

    // Optimistic UI update
    const itemRow = checkbox.closest("[data-checklist-item]")
    if (itemRow) {
      itemRow.classList.toggle("opacity-60", checked)
      const label = itemRow.querySelector("[data-checklist-label]")
      if (label) label.classList.toggle("line-through", checked)
    }

    this._updateProgress()

    // Send fetch to server
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": csrfToken || "",
        "Accept": "application/json"
      },
      credentials: "same-origin",
      body: `key=${encodeURIComponent(key)}`
    }).then(res => {
      if (!res.ok) {
        // Revert on failure
        checkbox.checked = !checked
        if (itemRow) {
          itemRow.classList.toggle("opacity-60", !checked)
          const label = itemRow.querySelector("[data-checklist-label]")
          if (label) label.classList.toggle("line-through", !checked)
        }
        this._updateProgress()
      }
      return res.json()
    }).then(data => {
      if (data && data.ready !== undefined) {
        this._updateSubmitGate(data.ready)
      }
    }).catch(() => {
      checkbox.checked = !checked
      if (itemRow) {
        itemRow.classList.toggle("opacity-60", !checked)
        const label = itemRow.querySelector("[data-checklist-label]")
        if (label) label.classList.toggle("line-through", !checked)
      }
      this._updateProgress()
    })
  }

  _updateProgress() {
    const checkboxes = this.element.querySelectorAll("input[type='checkbox']")
    const total = checkboxes.length
    const checked = Array.from(checkboxes).filter(cb => cb.checked).length
    const pct = total > 0 ? Math.round((checked / total) * 100) : 0

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${pct}%`
      // Switch between primary fill (incomplete) and the "category-new" green
      // (complete). The oklch arbitrary value matches the hardcoded one in
      // the ERB views — var() with /alpha inside bracket syntax does not
      // produce valid CSS in Tailwind v4.
      this.progressBarTarget.classList.toggle("bg-[oklch(0.72_0.19_142.5/0.7)]", pct === 100)
      this.progressBarTarget.classList.toggle("bg-primary/60", pct !== 100)
    }

    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `${checked}/${total} (${pct}%)`
    }
  }

  _updateSubmitGate(ready) {
    if (!this.hasSubmitGateTarget) return
    if (ready) {
      this.submitGateTarget.classList.remove("hidden")
    } else {
      this.submitGateTarget.classList.add("hidden")
    }
  }
}
