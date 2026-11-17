import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["type", "scheduled", "date", "isoDate"]

  connect() {
    const minimum = new Date(Date.now() + 65 * 60 * 1000)
    this.dateTarget.min = new Date(minimum.getTime() - minimum.getTimezoneOffset() * 60000).toISOString().slice(0, 16)
    this.toggleScheduled()
  }

  toggleScheduled() {
    const scheduled = this.typeTargets.some(input => input.checked && input.value === "SCHEDULED")
    this.scheduledTarget.style.display = scheduled ? "" : "none"
    this.dateTarget.required = scheduled
    this.dateTarget.disabled = !scheduled
    this.prepare()
  }

  prepare() {
    const date = this.dateTarget.disabled ? null : new Date(this.dateTarget.value)
    this.isoDateTarget.value = date && !Number.isNaN(date.getTime()) ? date.toISOString() : ""
  }
}
