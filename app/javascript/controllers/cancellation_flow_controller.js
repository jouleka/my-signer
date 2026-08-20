import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "reason", "nextButton", "offerPanel", "feedbackField", "reasonLabel", "feedbackTag"]
  static values = {
    planTier: String,
    billingInterval: String,
    hasLowerPaidTier: Boolean
  }

  connect() {
    this.currentStep = 0
    this.selectedReason = null
    this.selectedTags = new Set()
    this.showStep(0)
  }

  selectReason(event) {
    this.selectedReason = event.currentTarget.dataset.reason
    this.reasonTargets.forEach(el => {
      el.classList.toggle("ring-2", el.dataset.reason === this.selectedReason)
      el.classList.toggle("ring-primary", el.dataset.reason === this.selectedReason)
      el.classList.toggle("bg-primary/5", el.dataset.reason === this.selectedReason)
      el.classList.toggle("border-transparent", el.dataset.reason === this.selectedReason)
    })
    this.nextButtonTarget.disabled = false
  }

  toggleTag(event) {
    const btn = event.currentTarget
    const tag = btn.textContent.trim()

    if (this.selectedTags.has(tag)) {
      this.selectedTags.delete(tag)
      btn.classList.remove("ring-2", "ring-primary", "bg-primary/5", "border-transparent")
    } else {
      this.selectedTags.add(tag)
      btn.classList.add("ring-2", "ring-primary", "bg-primary/5", "border-transparent")
    }
  }

  next() {
    if (this.currentStep === 0 && !this.selectedReason) return
    this.currentStep++
    this.showStep(this.currentStep)
    if (this.currentStep === 1) {
      this.showPersonalizedOffer()
    }
  }

  back() {
    if (this.currentStep > 0) {
      this.currentStep--
      this.showStep(this.currentStep)
    }
  }

  reset() {
    this.currentStep = 0
    this.selectedReason = null
    this.selectedTags = new Set()
    this.reasonTargets.forEach(el => {
      el.classList.remove("ring-2", "ring-primary", "bg-primary/5", "border-transparent")
    })
    this.feedbackTagTargets.forEach(el => {
      el.classList.remove("ring-2", "ring-primary", "bg-primary/5", "border-transparent")
    })
    if (this.hasNextButtonTarget) this.nextButtonTarget.disabled = true
    if (this.hasFeedbackFieldTarget) this.feedbackFieldTarget.value = ""
    this.showStep(0)
  }

  showStep(index) {
    this.stepTargets.forEach((step, i) => {
      step.classList.toggle("hidden", i !== index)
    })
  }

  get isMonthly() {
    return this.billingIntervalValue === "monthly"
  }

  get canDowngrade() {
    return this.hasLowerPaidTierValue
  }

  get annualSavingTip() {
    return this.isMonthly
      ? " Or switch to annual billing to save over 30%."
      : ""
  }

  showPersonalizedOffer() {
    const canDowngrade = this.canDowngrade
    const isMonthly = this.isMonthly

    let expensiveOffer
    if (canDowngrade && isMonthly) {
      expensiveOffer = {
        icon: "fa-solid fa-arrow-trend-down",
        title: "Would a smaller plan work?",
        body: "You can downgrade to a lower tier to keep access at a reduced price, or switch to annual billing to save over 30%."
      }
    } else if (canDowngrade) {
      expensiveOffer = {
        icon: "fa-solid fa-arrow-trend-down",
        title: "Would a smaller plan work?",
        body: "You can downgrade to a lower tier to reduce your costs while keeping access to the core features."
      }
    } else if (isMonthly) {
      expensiveOffer = {
        icon: "fa-solid fa-calendar",
        title: "Switch to annual and save over 30%",
        body: "You're on monthly billing. Switching to annual locks in a lower rate and keeps everything you have today."
      }
    } else {
      expensiveOffer = {
        icon: "fa-solid fa-message",
        title: "We hear you on pricing",
        body: "You're already on annual billing at our best rate. Let us know in the next step what would make this worth it for you."
      }
    }

    const downgradeHint = canDowngrade
      ? "You could downgrade to a smaller plan and upgrade again later."
      : "You can always re-subscribe when you're ready. Your data stays safe."

    const offers = {
      expensive: expensiveOffer,
      not_using: {
        icon: "fa-solid fa-pause",
        title: "Take a break instead?",
        body: `If you're not using it right now, that's okay. ${downgradeHint}${!canDowngrade ? this.annualSavingTip : ""}`
      },
      missing_features: {
        icon: "fa-solid fa-lightbulb",
        title: "Help us build what you need",
        body: "We ship updates regularly. Tell us what's missing in the next step and we'll factor it into our roadmap."
      },
      switching: {
        icon: "fa-solid fa-shuffle",
        title: "Anything we can do differently?",
        body: "We'd love to know what the other tool does better so we can improve. Let us know in the next step."
      },
      temporary: {
        icon: "fa-solid fa-clock-rotate-left",
        title: "You can come back anytime",
        body: `If this is just a timing thing, no worries. ${downgradeHint}`
      },
      other: {
        icon: "fa-solid fa-message",
        title: "We'd love to hear from you",
        body: "Whatever the reason, your feedback helps us build a better product. Let us know in the next step."
      }
    }

    const offer = offers[this.selectedReason] || offers.other
    this.offerPanelTargets.forEach(panel => {
      panel.querySelector("[data-offer-icon]").className = `${offer.icon} text-sm text-primary`
      panel.querySelector("[data-offer-title]").textContent = offer.title
      panel.querySelector("[data-offer-body]").textContent = offer.body
    })

    if (this.hasReasonLabelTarget) {
      const labels = {
        expensive: "Too expensive",
        not_using: "Not using it enough",
        missing_features: "Missing features",
        switching: "Switching tools",
        temporary: "Temporary",
        other: "Other"
      }
      this.reasonLabelTarget.textContent = labels[this.selectedReason] || "Other"
    }
  }
}
