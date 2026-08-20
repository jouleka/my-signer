import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "eyebrow", "title", "message", "suggestion", "cta", "ctaLabel"]
  static values = {
    initialPayload: Object,
    pricingPath: String
  }

  connect() {
    this.boundOpen = this.openFromEvent.bind(this)
    document.addEventListener("mysigner:upgrade-prompt", this.boundOpen)

    if (this.hasInitialPayloadValue && Object.keys(this.initialPayloadValue || {}).length > 0) {
      requestAnimationFrame(() => this.present(this.initialPayloadValue, { scroll: false }))
    }
  }

  disconnect() {
    document.removeEventListener("mysigner:upgrade-prompt", this.boundOpen)
  }

  openFromEvent(event) {
    this.present(event.detail || {}, { scroll: true })
  }

  close() {
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  present(payload, options = {}) {
    if (!payload || Object.keys(payload).length === 0 || !this.hasPanelTarget) return

    const currentPlan = (payload.current_plan || "free").toString()
    const requiredPlan = payload.required_plan ? payload.required_plan.toString() : ""
    const feature = (payload.feature || "this feature").toString()
    const title = payload.title || (requiredPlan ? `Upgrade to ${this.titleize(requiredPlan)}` : "Need more capacity?")
    const message = payload.message || (requiredPlan
      ? `Your ${this.titleize(currentPlan)} plan doesn't include ${feature}.`
      : `Your ${this.titleize(currentPlan)} plan has reached its current limit for ${feature}.`)
    const suggestion = payload.suggestion || (requiredPlan
      ? `Upgrade from ${this.titleize(currentPlan)} to ${this.titleize(requiredPlan)} to continue.`
      : `Contact support if you need more room for ${feature}.`)

    if (this.hasEyebrowTarget) {
      this.eyebrowTarget.textContent = requiredPlan ? `${this.titleize(currentPlan)} to ${this.titleize(requiredPlan)}` : this.titleize(currentPlan)
    }
    if (this.hasTitleTarget) this.titleTarget.textContent = title
    if (this.hasMessageTarget) this.messageTarget.textContent = message
    if (this.hasSuggestionTarget) this.suggestionTarget.textContent = suggestion

    if (this.hasCtaTarget) {
      this.ctaTarget.href = this.pricingUrl(requiredPlan)
    }

    if (this.hasCtaLabelTarget) {
      this.ctaLabelTarget.textContent = requiredPlan ? `See ${this.titleize(requiredPlan)} plan` : "See plans"
    }

    this.panelTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")

    if (options.scroll) {
      requestAnimationFrame(() => {
        this.panelTarget.scrollIntoView({ behavior: "smooth", block: "center" })
      })
    }
  }

  pricingUrl(requiredPlan) {
    const basePath = this.hasPricingPathValue ? this.pricingPathValue : "/pricing"
    return requiredPlan ? `${basePath}#plan-${requiredPlan}` : `${basePath}#plans-grid`
  }

  titleize(value) {
    return value.toString().replace(/_/g, " ").replace(/\b\w/g, char => char.toUpperCase())
  }
}
