import { Controller } from "@hotwired/stimulus"

// Renders a Cloudflare Turnstile widget (explicit mode) into this element.
// Explicit rendering — rather than api.js auto-scanning `.cf-turnstile` once
// on load — keeps the widget working across Turbo navigations, 422
// re-renders and turbo-stream form replacements. The token is posted as
// `cf-turnstile-response` and verified server-side by TurnstileProtection.
const SCRIPT_URL = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
let loadPromise

function loadTurnstile() {
  if (window.turnstile) return Promise.resolve(window.turnstile)
  if (loadPromise) return loadPromise

  loadPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = SCRIPT_URL
    script.onload = () => resolve(window.turnstile)
    script.onerror = () => {
      loadPromise = null
      reject(new Error("Unable to load Cloudflare Turnstile"))
    }
    document.head.appendChild(script)
  })

  return loadPromise
}

export default class extends Controller {
  static values = { siteKey: String, action: String }

  async connect() {
    // Turnstile tokens are single-use: get a fresh one after every Turbo
    // submission (e.g. a contact-form validation error that keeps the form).
    this.form = this.element.closest("form")
    this.onSubmitEnd = () => this.reset()
    this.form?.addEventListener("turbo:submit-end", this.onSubmitEnd)

    try {
      const turnstile = await loadTurnstile()
      if (!this.element.isConnected || this.widgetId !== undefined) return

      // Drop a stale iframe restored from a Turbo cache snapshot.
      this.element.replaceChildren()
      this.widgetId = turnstile.render(this.element, {
        sitekey: this.siteKeyValue,
        action: this.actionValue || undefined,
        theme: "auto",
        size: "flexible"
      })
    } catch (error) {
      console.error(error)
    }
  }

  disconnect() {
    this.form?.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    if (this.widgetId !== undefined && window.turnstile) {
      window.turnstile.remove(this.widgetId)
    }
    this.widgetId = undefined
  }

  reset() {
    if (this.widgetId !== undefined && window.turnstile) {
      window.turnstile.reset(this.widgetId)
    }
  }
}
