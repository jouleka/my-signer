import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="time-savings"
const BASE_HOURS_PER_RELEASE = 0.0

export default class extends Controller {
  static targets = [
    "releasesInput",
    "releasesValue",
    "hoursValue",
    "annualHours",
    "annualDays",
    "summary",
    "ctaNote",
    "platformInput",
    "platformLabel"
  ]

  connect() {
    this.update()
  }

  update() {
    const releasesPerMonth = this._readNumber(this.releasesInputTarget, 12)

    let platformHours = 0
    if (this.hasPlatformInputTarget) {
      this.platformInputTargets.forEach((el) => {
        if (el.checked) {
          const h = parseFloat(el.dataset.hours || "0")
          if (Number.isFinite(h)) platformHours += h
        }
      })
    }
    const selectedPlatforms = this.hasPlatformInputTarget
      ? this.platformInputTargets.filter((el) => el.checked).length
      : 0

    const hoursPerRelease = selectedPlatforms === 0
      ? 0
      : BASE_HOURS_PER_RELEASE + platformHours
    // Toggle selected border on labels to show active state
    if (this.hasPlatformLabelTarget && this.hasPlatformInputTarget) {
      this.platformInputTargets.forEach((input, idx) => {
        const label = this.platformLabelTargets[idx]
        if (!label) return
        label.classList.toggle("border-base-content", input.checked)
      })
    }

    const annualHours = Math.round(releasesPerMonth * 12 * hoursPerRelease)
    const workingDays = Math.round(annualHours / 8)
    const workingMonths = Math.round(workingDays / 20)

    if (this.hasReleasesValueTarget) this.releasesValueTargets.forEach((el) => {
      el.textContent = String(releasesPerMonth)
    })
    if (this.hasHoursValueTarget) this.hoursValueTargets.forEach((el) => {
      el.textContent = `${this._formatOneDecimal(hoursPerRelease)}h`
    })
    if (this.hasAnnualHoursTarget) this.annualHoursTarget.textContent = `${annualHours}h`
    if (this.hasAnnualDaysTarget) this.annualDaysTarget.textContent = `= ${workingDays} working days${workingMonths > 0 ? ` (~${workingMonths} mo)` : ""}!`

    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = selectedPlatforms === 0
        ? "Select at least one platform to estimate your savings."
        : `That's roughly ${workingDays} working days back every year!`
    }

    if (this.hasCtaNoteTarget) {
      this.ctaNoteTarget.textContent = annualHours > 0 ? `Estimated: Save ~${annualHours}h/yr` : ""
    }
  }

  _readNumber(element, fallback) {
    const value = parseFloat(element?.value)
    return Number.isFinite(value) ? value : fallback
  }

  _formatOneDecimal(value) {
    return Math.round(value * 10) / 10
  }
}


