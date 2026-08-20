import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["radio", "scheduledFields"]

  connect() {
    this.toggle()
  }

  toggle() {
    const selected = this.radioTargets.find(r => r.checked)?.value
    if (this.hasScheduledFieldsTarget) {
      this.scheduledFieldsTarget.classList.toggle("hidden", selected !== "SCHEDULED")
    }
  }
}
