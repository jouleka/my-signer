import { Controller } from "@hotwired/stimulus"

// Enforces the max-countries-per-keyword entitlement at submit time in
// the add-tracked-keyword modal. Keeps selection within the limit by
// undoing the most recent checkbox toggle when the cap is exceeded,
// and briefly flashes the parent label red for feedback.
export default class extends Controller {
  static targets = ["keywordInput", "countryGrid"]
  static values = { maxKeywords: Number, maxCountries: Number }

  connect() {
    this.prefillFromUrl()
  }

  // Opens the Add-tracked-keyword modal with the keyword prefilled when the
  // URL carries ?prefill_keyword=foo. Used by the Scratchpad "Track" link so
  // clicking it on the Suggestions tab lands the user on the Tracking tab with
  // the modal already open and the keyword populated.
  prefillFromUrl() {
    const params = new URLSearchParams(window.location.search)
    const keyword = params.get("prefill_keyword")
    if (!keyword) return
    if (this.hasKeywordInputTarget) {
      this.keywordInputTarget.value = decodeURIComponent(keyword)
    }
    const dialog = document.getElementById("add-tracked-keyword-modal")
    if (dialog && typeof dialog.showModal === "function" && !dialog.open) {
      dialog.showModal()
    }
  }

  enforceCountryLimit(event) {
    const checked = this.countryGridTarget.querySelectorAll("[data-country-checkbox]:checked")
    if (checked.length > this.maxCountriesValue) {
      event.target.checked = false
      const parent = event.target.parentElement
      if (parent) {
        parent.classList.add("bg-error/10")
        setTimeout(() => parent.classList.remove("bg-error/10"), 600)
      }
    }
  }
}
