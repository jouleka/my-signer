import { Controller } from "@hotwired/stimulus"

// Drives the four-bar strength meter on the editorial sign-up / reset
// pages. Listens to input on the password field, computes a 0–4 score
// (length + composition + repeat / common-pattern penalties), and paints
// the bars + summary line inline. Sits alongside form_validator on the
// same input — form_validator owns validation/error UX, this controller
// only owns the meter.
//
// We do NOT call HaveIBeenPwned (or any other breach API) from this file.
// Copy reflects that — the meter measures structural strength of what's
// typed, not whether it's appeared in a public dump.
export default class extends Controller {
  static targets = ["bar", "summary"]

  static values = {
    minLength: { type: Number, default: 12 }
  }

  // A handful of common passwords / patterns to penalize. Not a real
  // dictionary — just a guard so trivially weak entries can't reach the
  // top "Excellent" rung. For real breach-list checks see HIBP k-anonymity.
  static COMMON_PATTERNS = [
    "password", "passw0rd", "qwerty", "qwertyuiop", "letmein", "welcome",
    "admin", "iloveyou", "monkey", "dragon", "abc123", "111111", "123123",
    "12345", "123456", "1234567", "12345678", "123456789", "1234567890"
  ]

  connect() {
    const input = this.element.querySelector('input[type="password"]')
    if (input) this.paint(input.value || "")
  }

  update(event) {
    this.paint(event.target.value || "")
  }

  paint(value) {
    const score = this.score(value)
    this.barTargets.forEach((bar, i) => {
      const fill = bar.querySelector("span")
      if (!fill) return
      const active = i < score
      fill.style.width = active ? "100%" : "0%"
      fill.style.background = active ? this.colorFor(score) : "transparent"
    })
    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = this.summaryFor(value, score)
      this.summaryTarget.style.color = value
        ? `color-mix(in oklab, ${this.colorFor(score)} 95%, transparent)`
        : "color-mix(in oklab, var(--color-base-content) 50%, transparent)"
    }
  }

  score(value) {
    if (!value) return 0
    let s = 0
    if (value.length >= 8) s += 1
    if (value.length >= this.minLengthValue) s += 1
    const classes = [/[a-z]/, /[A-Z]/, /\d/, /[^A-Za-z0-9]/].filter((r) => r.test(value)).length
    if (classes >= 2) s += 1
    if (classes >= 3 && value.length >= this.minLengthValue) s += 1

    // Penalties — each caps the score so trivially weak inputs can't reach
    // the top rung even with length + class bonuses.
    if (this.hasLowEntropy(value)) s = Math.min(s, 1)
    if (this.matchesCommonPattern(value)) s = Math.min(s, 1)

    return Math.min(s, 4)
  }

  // Flags low-entropy structures: long runs of the same char (aaaa, 1111),
  // simple ascending / descending sequences (1234, abcd, 9876), or strings
  // dominated by a single character (e.g. "Aaaaaaaaaaa1!" — 4 distinct chars
  // out of 14 = 0.28 ratio, well under the 0.45 threshold).
  hasLowEntropy(value) {
    if (/(.)\1{2,}/.test(value)) return true
    if (this.hasSequentialRun(value, 4)) return true
    const distinct = new Set(value).size
    if (distinct / value.length < 0.45) return true
    return false
  }

  hasSequentialRun(value, runLength) {
    let asc = 1
    let desc = 1
    for (let i = 1; i < value.length; i++) {
      const delta = value.charCodeAt(i) - value.charCodeAt(i - 1)
      asc = delta === 1 ? asc + 1 : 1
      desc = delta === -1 ? desc + 1 : 1
      if (asc >= runLength || desc >= runLength) return true
    }
    return false
  }

  matchesCommonPattern(value) {
    const lower = value.toLowerCase()
    return this.constructor.COMMON_PATTERNS.some((p) => lower.includes(p))
  }

  colorFor(score) {
    if (score <= 1) return "var(--color-error)"
    if (score === 2) return "var(--color-warning)"
    return "var(--color-success)"
  }

  summaryFor(value, score) {
    if (!value) return `Use ${this.minLengthValue}+ characters with letters, numbers, and a symbol.`
    if (score <= 1) return "Weak — avoid repeats / common patterns and mix character types."
    if (score === 2) return "Fair — try mixing in another character class."
    if (score === 3) return "Strong — three more characters and it'd be excellent."
    return "Excellent — long and varied."
  }
}
