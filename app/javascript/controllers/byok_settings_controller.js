import { Controller } from "@hotwired/stimulus"

// Drives the BYOK panel's Verify button. POSTs the current ARN value to the
// /verify endpoint and renders the result inline next to the input, without
// reloading the page. Save and Clear are plain form submits (Rails handles
// them); only Verify needs JS because it returns JSON instead of a redirect.
export default class extends Controller {
  static targets = ["arn", "result"]
  static values = { verifyUrl: String }

  async verify() {
    const arn = this.arnTarget.value.trim()
    this.show("Checking…", "text-base-content/60")

    try {
      const response = await fetch(this.verifyUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({ byok_kms_key_arn: arn })
      })
      const data = await response.json()
      if (data.ok) {
        this.show("Verified. This ARN is reachable and the key policy condition is in place.", "text-success")
      } else {
        this.show(data.error || "Verification failed.", "text-error")
      }
    } catch (err) {
      this.show(`Network error: ${err.message}`, "text-error")
    }
  }

  show(message, tone) {
    const el = this.resultTarget
    el.textContent = message
    el.className = `mt-2 text-xs ${tone}`
  }

  csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
