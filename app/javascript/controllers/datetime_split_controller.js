import { Controller } from "@hotwired/stimulus"

// Splits a datetime-local input into separate date + time inputs
// for better mobile UX (native date/time pickers are mobile-friendly).
// Syncs the split values back into a hidden field for form submission.
export default class extends Controller {
  static targets = ["hidden", "date", "time"]

  connect() {
    this.populateFromHidden()
    this.setMinDate()
  }

  populateFromHidden() {
    const val = this.hiddenTarget.value
    if (!val) return

    // datetime-local value format: "2026-02-11T21:54"
    const [datePart, timePart] = val.split("T")
    if (datePart) this.dateTarget.value = datePart
    if (timePart) this.timeTarget.value = timePart.slice(0, 5)
  }

  setMinDate() {
    const minDate = new Date(Date.now() + 2 * 60 * 60 * 1000) // 2 hours buffer
    this.dateTarget.min = minDate.toISOString().slice(0, 10)
  }

  sync() {
    const date = this.dateTarget.value
    const time = this.timeTarget.value || "00:00"

    if (date) {
      this.hiddenTarget.value = `${date}T${time}`
    } else {
      this.hiddenTarget.value = ""
    }
  }
}
