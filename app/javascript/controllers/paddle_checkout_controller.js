import { Controller } from "@hotwired/stimulus"
import { ensurePaddle, subscribeToPaddleEvents } from "lib/paddle_loader"

const FRAME_CLASS = "mysigner-paddle-frame"

export default class extends Controller {
  static values = {
    token: String,
    environment: String,
    email: String,
    userId: Number,
    checkoutCompleteUrl: String,
    returnTo: String
  }

  static targets = ["dialog", "spinner", "title", "frame"]

  connect() {
    this.unsubscribe = subscribeToPaddleEvents(this.handlePaddleEvent.bind(this))
    this.activeSelection = null
    this.checkoutOpen = false
  }

  disconnect() {
    this.unsubscribe?.()
  }

  async open(event) {
    event.preventDefault()

    const { priceId, planTier, billingInterval } = event.params
    if (!priceId || !this.hasTokenValue) return

    this.activeSelection = { planTier, billingInterval }
    this.showDialog(planTier, billingInterval)

    try {
      const Paddle = await ensurePaddle({
        token: this.tokenValue,
        environment: this.environmentValue || "live",
        defaultTheme: this.paddleTheme()
      })

      const checkout = {
        items: [ { priceId, quantity: 1 } ],
        settings: {
          displayMode: "inline",
          theme: this.paddleTheme(),
          frameTarget: FRAME_CLASS,
          frameInitialHeight: "600",
          frameStyle: "width: 100%; min-width: 312px; background-color: transparent; border: none;"
        },
        customData: {
          user_id: this.userIdValue,
          plan_tier: planTier,
          billing_interval: billingInterval
        }
      }

      if (this.hasEmailValue && this.emailValue) {
        checkout.customer = { email: this.emailValue }
      }

      window.Paddle.Checkout.open(checkout)
      this.checkoutOpen = true
    } catch (error) {
      this.closeDialog()
      window.alert("Unable to open Paddle checkout right now.")
    }
  }

  close(event) {
    event?.preventDefault()
    this.teardownCheckout()
    this.closeDialog()
  }

  async handlePaddleEvent(event) {
    if (!event) return

    if (event.name === "checkout.loaded" && this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
      return
    }

    if (event.name === "checkout.closed") {
      this.closeDialog()
      this.checkoutOpen = false
      return
    }

    if (event.name !== "checkout.completed" || !this.activeSelection) return

    try {
      const payload = await this.confirmCheckout(event.data?.transaction_id)
      this.navigateTo(payload?.redirect_url)
    } catch (error) {
      this.navigateTo(this.returnToValue || window.location.pathname)
    } finally {
      this.activeSelection = null
      this.teardownCheckout()
    }
  }

  async confirmCheckout(transactionId) {
    for (let attempt = 0; attempt < 6; attempt += 1) {
      const payload = await this.postCheckoutCompletion(transactionId)
      if (payload?.activated || payload?.ok === false) return payload
      await this.delay(payload?.retry_after_ms || 1200)
    }

    return { redirect_url: this.returnToValue || window.location.pathname }
  }

  async postCheckoutCompletion(transactionId) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrfToken || !this.hasCheckoutCompleteUrlValue) {
      throw new Error("Missing checkout completion configuration")
    }

    const response = await fetch(this.checkoutCompleteUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({
        transaction_id: transactionId,
        return_to: this.returnToValue || window.location.pathname,
        expected_plan_tier: this.activeSelection?.planTier,
        expected_billing_interval: this.activeSelection?.billingInterval
      })
    })

    return response.json()
  }

  navigateTo(url) {
    const destination = url || this.returnToValue || window.location.pathname
    if (window.Turbo?.visit) {
      window.Turbo.visit(destination, { action: "replace" })
      return
    }

    window.location.assign(destination)
  }

  delay(ms) {
    return new Promise(resolve => window.setTimeout(resolve, ms))
  }

  showDialog(planTier, billingInterval) {
    if (!this.hasDialogTarget) return

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = this.titleFor(planTier, billingInterval)
    }

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }

    if (this.hasFrameTarget) {
      this.frameTarget.replaceChildren()
    }

    if (typeof this.dialogTarget.showModal === "function" && !this.dialogTarget.open) {
      this.dialogTarget.showModal()
    }
  }

  closeDialog() {
    if (!this.hasDialogTarget) return
    if (this.dialogTarget.open) this.dialogTarget.close()
    if (this.hasFrameTarget) this.frameTarget.replaceChildren()
  }

  teardownCheckout() {
    if (!this.checkoutOpen) return
    try {
      window.Paddle?.Checkout?.close?.()
    } catch (_error) {
      // Paddle throws if there's no active checkout — ignore.
    }
    this.checkoutOpen = false
  }

  titleFor(planTier, billingInterval) {
    const tier = planTier ? `${planTier[0].toUpperCase()}${planTier.slice(1)}` : "Plan"
    const interval = billingInterval === "yearly" ? "Yearly" : billingInterval === "monthly" ? "Monthly" : ""
    return interval ? `Upgrade to ${tier} · ${interval}` : `Upgrade to ${tier}`
  }

  // Paddle reads `theme` from settings and shades the inline iframe chrome
  // to match. Reads the live <html data-theme> so it follows the user toggle.
  paddleTheme() {
    const theme = document.documentElement.dataset.theme || ""
    return theme.includes("light") ? "light" : "dark"
  }
}
