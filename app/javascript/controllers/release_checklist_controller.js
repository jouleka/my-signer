import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progressBar", "progressText", "progressPercent", "submitGate", "readyBadge", "error"]

  async toggle(event) {
    const checkbox = event.currentTarget
    const checked = checkbox.checked
    const url = checked ? checkbox.dataset.releaseChecklistCheckUrl : checkbox.dataset.releaseChecklistUncheckUrl
    const key = checkbox.dataset.releaseChecklistKeyParam
    if (!key || !url) return

    checkbox.disabled = true
    this.errorTarget.classList.add("hidden")
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
          "Accept": "application/json"
        },
        credentials: "same-origin",
        body: `key=${encodeURIComponent(key)}`
      })
      const data = await response.json()
      if (!response.ok || response.redirected) throw new Error(data.error || "Could not save checklist. Please try again.")
      const row = checkbox.closest("[data-checklist-item]")
      row.classList.toggle("opacity-60", checked)
      row.querySelector("[data-checklist-label]").classList.toggle("line-through", checked)
      this.progressBarTarget.style.width = `${data.completion}%`
      this.progressBarTarget.classList.toggle("bg-[oklch(0.72_0.19_142.5/0.7)]", data.completion === 100)
      this.progressBarTarget.classList.toggle("bg-primary/60", data.completion !== 100)
      this.progressPercentTarget.textContent = `${data.completion}%`
      this.progressTextTarget.textContent = `${data.checked}/${data.total}`
      this.submitGateTarget.classList.toggle("hidden", !data.ready)
      this.readyBadgeTarget.classList.toggle("hidden", !data.ready)
    } catch (error) {
      checkbox.checked = !checked
      this.errorTarget.textContent = "Could not save checklist. Please try again."
      this.errorTarget.classList.remove("hidden")
    } finally {
      checkbox.disabled = false
    }
  }
}
