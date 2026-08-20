import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    defaultInterval: { type: String, default: "yearly" },
    previewUrl: String,
    returnTo: String
  }

  static targets = [
    "intervalOption",
    "intervalPanel",
    "intervalCopy",
    "card",
    "grid",
    "savingsLine",
    "previewModal",
    "previewTitle",
    "previewTiming",
    "previewMessage",
    "previewDueToday",
    "previewNextCharge",
    "previewRecurringCharge",
    "previewSummary",
    "previewWarnings",
    "previewWarningsContainer",
    "previewError",
    "previewLoading",
    "previewSubmit",
    "previewPlanTierInput",
    "previewBillingIntervalInput",
    "previewReturnToInput"
  ]

  connect() {
    this._scheduleCardReveal();
    this.selectedInterval = this.defaultIntervalValue || "yearly"
    this.syncIntervalUI()
  }

  _scheduleCardReveal() {
    if (!this.hasCardTarget) return;
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.cardTargets.forEach((c) => {
        c.style.opacity = "1";
        c.style.transform = "none";
      });
      return;
    }

    this.cardTargets.forEach((card) => {
      card.style.opacity = "0";
      card.style.transform = "translateY(20px)";
      card.style.transition = "opacity 400ms cubic-bezier(0.2, 0.6, 0.2, 1), transform 400ms cubic-bezier(0.2, 0.6, 0.2, 1)";
    });

    const obs = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const i = this.cardTargets.indexOf(entry.target);
        setTimeout(() => {
          entry.target.style.opacity = "1";
          entry.target.style.transform = "translateY(0)";
        }, i * 80);
        obs.unobserve(entry.target);
      });
    }, { threshold: 0.15 });

    this.cardTargets.forEach((c) => obs.observe(c));
  }

  selectInterval(event) {
    event.preventDefault()
    this.selectedInterval = event.params.interval
    this.syncIntervalUI()
    this._updateSavingsLine(this.selectedInterval)
  }

  // Prospect-tier CTA. cta_data_attrs binds this under
  // `action: "click->pricing-plans#goToSignup"` for Start-for-free /
  // Start-14-day-Pro-trial / Go-Team buttons. All three route to the
  // single signup form — the tier gets chosen after registration.
  goToSignup(event) {
    event.preventDefault()
    const path = "/users/sign_up"
    if (window.Turbo?.visit) {
      window.Turbo.visit(path, { action: "advance" })
    } else {
      window.location.assign(path)
    }
  }

  // Trialing-user CTA on the Free card. Opens whichever end-of-trial /
  // cancellation modal is on the page:
  //   - `#trial-end-modal` for users on an active 14-day reverse trial
  //     (rendered by app/views/pricing/_trial_end_modal.html.erb). This
  //     is the common case — trial users have no Paddle subscription.
  //   - `#billing-cancel-modal` for users with a real paid subscription
  //     (rendered by app/views/pricing/_cancellation_modal.html.erb).
  // Older versions of this app only checked the second ID, so the
  // button silently no-op'd for trial users (the only ones who actually
  // see the "End trial" label).
  openEndTrial(event) {
    event.preventDefault()
    const modal =
      document.getElementById("trial-end-modal") ||
      document.getElementById("billing-cancel-modal")
    if (modal && typeof modal.showModal === "function" && !modal.open) {
      modal.showModal()
    }
  }

  async openPreview(event) {
    event.preventDefault()
    if (!this.hasPreviewModalTarget || !this.hasPreviewUrlValue) return

    const { planTier, billingInterval, label } = event.params
    this.previewPlanTierInputTarget.value = planTier
    this.previewBillingIntervalInputTarget.value = billingInterval
    this.previewReturnToInputTarget.value = this.returnToValue || window.location.pathname

    this.previewTitleTarget.textContent = label || `${planTier} ${billingInterval}`
    this.previewTimingTarget.textContent = "Loading preview"
    this.previewMessageTarget.textContent = "Fetching billing details from Paddle."
    this.previewSummaryTarget.textContent = ""
    this.previewErrorTarget.textContent = ""
    while (this.previewWarningsTarget.firstChild) {
      this.previewWarningsTarget.removeChild(this.previewWarningsTarget.firstChild)
    }
    if (this.hasPreviewWarningsContainerTarget) {
      this.previewWarningsContainerTarget.classList.add("hidden")
    }
    this.previewDueTodayTarget.textContent = "..."
    this.previewNextChargeTarget.textContent = "..."
    this.previewRecurringChargeTarget.textContent = "..."
    this.previewSubmitTarget.disabled = true
    this.previewLoadingTarget.classList.remove("hidden")

    this.previewModalTarget.showModal()

    try {
      const payload = await this.fetchPreview(planTier, billingInterval)
      if (!payload.ok) {
        throw new Error(payload.error || "Unable to preview this change.")
      }

      this.renderPreview(payload.preview, payload.warnings || [])
      this.previewSubmitTarget.disabled = false
    } catch (error) {
      this.previewErrorTarget.textContent = error.message
    } finally {
      this.previewLoadingTarget.classList.add("hidden")
    }
  }

  syncIntervalUI() {
    this.intervalOptionTargets.forEach((element) => {
      const active = element.dataset.interval === this.selectedInterval
      element.setAttribute("aria-pressed", active ? "true" : "false")
      element.classList.toggle("bg-neutral", active)
      element.classList.toggle("text-neutral-content", active)
      element.classList.toggle("shadow-sm", active)
    })

    this.intervalPanelTargets.forEach((element) => {
      element.classList.toggle("hidden", element.dataset.interval !== this.selectedInterval)
    })

    this.intervalCopyTargets.forEach((element) => {
      element.classList.toggle("hidden", element.dataset.interval !== this.selectedInterval)
    })
  }

  closePreview(event) {
    event?.preventDefault()
    if (this.hasPreviewModalTarget && this.previewModalTarget.open) {
      this.previewModalTarget.close()
    }
  }

  async fetchPreview(planTier, billingInterval) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(this.previewUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({
        plan_tier: planTier,
        billing_interval: billingInterval
      })
    })

    return response.json()
  }

  renderPreview(preview, warnings) {
    this.previewTitleTarget.textContent = preview.title
    this.previewTimingTarget.textContent = preview.timing_label
    this.previewMessageTarget.textContent = preview.message
    this.previewDueTodayTarget.textContent = this.moneyText(preview.due_today, "No charge today")
    this.previewNextChargeTarget.textContent = this.moneyText(preview.next_charge)
    this.previewRecurringChargeTarget.textContent = this.moneyText(preview.recurring_charge)
    this.previewSummaryTarget.textContent = preview.summary_line || ""
    this.previewErrorTarget.textContent = ""

    // Clear existing warning items safely using DOM manipulation
    while (this.previewWarningsTarget.firstChild) {
      this.previewWarningsTarget.removeChild(this.previewWarningsTarget.firstChild)
    }

    if (warnings.length > 0) {
      warnings.forEach((warning) => {
        const li = document.createElement("li")
        li.textContent = warning
        this.previewWarningsTarget.appendChild(li)
      })
      if (this.hasPreviewWarningsContainerTarget) {
        this.previewWarningsContainerTarget.classList.remove("hidden")
      }
    } else if (this.hasPreviewWarningsContainerTarget) {
      this.previewWarningsContainerTarget.classList.add("hidden")
    }
  }

  moneyText(summary, zeroLabel = "No immediate charge") {
    if (!summary) return zeroLabel
    if (summary.amount_cents === 0) return zeroLabel

    const amount = summary.formatted_amount || zeroLabel
    return summary.formatted_date ? `${amount} on ${summary.formatted_date}` : amount
  }

  _updateSavingsLine(interval) {
    if (!this.hasSavingsLineTarget) return;
    this.savingsLineTarget.textContent =
      interval === "yearly"
        ? "Save up to $198/year on Team"
        : "Switch to yearly to save up to $198/year on Team";
  }
}
