import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "resultZone", "trackName", "meta", "seedList", "error"]
  static values = { url: String, country: String }

  connect() { this.debounceTimer = null }

  debouncedFetch() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetch(), 400)
  }

  async fetch() {
    const raw = this.inputTarget.value.trim()
    const match = raw.match(/\/id(\d+)/)
    if (!match) {
      this.showError("Paste an App Store URL that contains an app ID (…/id1234567890).")
      return
    }
    this.hideError()
    const appId = match[1]
    try {
      const token = document.querySelector("meta[name='csrf-token']")?.content
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": token || ""
        },
        body: JSON.stringify({ app_id: appId, country: this.countryValue })
      })
      if (response.status === 429) {
        this.showError("Too many lookups. Try again in a minute.")
        return
      }
      if (!response.ok) {
        this.showError("Couldn't reach Apple — try again in a moment.")
        return
      }
      const data = await response.json()
      this.renderResult(data)
    } catch (_) {
      this.showError("Network error.")
    }
  }

  renderResult(data) {
    this.resultZoneTarget.classList.remove("hidden")
    this.trackNameTarget.textContent = data.track_name || "—"
    this.metaTarget.textContent = [data.primary_genre, data.seller_name].filter(Boolean).join(" · ")
    this.seedListTarget.textContent = ""
    ;(data.seed_terms || []).forEach(seed => {
      const chip = document.createElement("button")
      chip.type = "button"
      chip.className = "px-2.5 py-1 text-xs rounded-full bg-primary/[0.08] text-primary/85 border border-primary/20 hover:bg-primary/[0.15] cursor-pointer"
      chip.textContent = seed
      chip.addEventListener("click", () => this.useSeed(seed))
      this.seedListTarget.appendChild(chip)
    })
  }

  useSeed(seed) {
    const section = document.querySelector("[data-controller~='keyword-editor']")
    if (!section) return
    const kwEditor = this.application.getControllerForElementAndIdentifier(section, "keyword-editor")
    if (!kwEditor?.hasSuggestionsInputTarget) return
    kwEditor.suggestionsInputTarget.value = seed
    kwEditor.fetchSuggestions()
    const dialog = document.getElementById("competitor-lookup-modal")
    dialog?.close?.()
  }

  showError(msg) { this.errorTarget.textContent = msg; this.errorTarget.classList.remove("hidden") }
  hideError()    { this.errorTarget.classList.add("hidden") }
}
