import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    delay: { type: Number, default: 300 },
    minLength: { type: Number, default: 0 }
  }
  static targets = ["input", "clearButton"]

  connect() {
    this.timeout = null
    this.updateClearButton()
    this.bindTurboEvents()
    this.restoreFocusIfNeeded()
  }

  disconnect() {
    this.unbindTurboEvents()
    if (this.focusRestoreTimeout) {
      clearTimeout(this.focusRestoreTimeout)
    }
  }

  bindTurboEvents() {
    this.turboBeforeFetchRequest = this.turboBeforeFetchRequest.bind(this)
    const form = this.form
    if (form) {
      form.addEventListener("turbo:before-fetch-request", this.turboBeforeFetchRequest)
    }
  }

  unbindTurboEvents() {
    const form = this.form
    if (form) {
      form.removeEventListener("turbo:before-fetch-request", this.turboBeforeFetchRequest)
    }
  }

  turboBeforeFetchRequest() {
    // Check if input has focus before form submission
    if (this.hasInputTarget && document.activeElement === this.inputTarget) {
      sessionStorage.setItem("autoSubmitRestoreFocus", "true")
      sessionStorage.setItem("autoSubmitSelectionStart", this.inputTarget.selectionStart.toString())
      sessionStorage.setItem("autoSubmitSelectionEnd", this.inputTarget.selectionEnd.toString())
    }
  }

  restoreFocusIfNeeded() {
    const shouldRestore = sessionStorage.getItem("autoSubmitRestoreFocus")
    if (shouldRestore === "true" && this.hasInputTarget) {
      // Try multiple times in case DOM isn't ready yet
      let attempts = 0
      const tryRestore = () => {
        attempts++
        if (this.hasInputTarget && document.contains(this.inputTarget)) {
          this.inputTarget.focus()
          const start = parseInt(sessionStorage.getItem("autoSubmitSelectionStart") || "0", 10)
          const end = parseInt(sessionStorage.getItem("autoSubmitSelectionEnd") || "0", 10)
          if (start !== undefined && end !== undefined) {
            this.inputTarget.setSelectionRange(start, end)
          }
          sessionStorage.removeItem("autoSubmitRestoreFocus")
          sessionStorage.removeItem("autoSubmitSelectionStart")
          sessionStorage.removeItem("autoSubmitSelectionEnd")
        } else if (attempts < 10) {
          // Retry up to 10 times
          this.focusRestoreTimeout = setTimeout(tryRestore, 50)
        }
      }
      requestAnimationFrame(() => {
        setTimeout(tryRestore, 0)
      })
    }
  }

  get form() {
    // If element is a form, use it directly; otherwise find closest parent form
    if (this.element.tagName === "FORM") {
      return this.element
    }
    return this.element.closest("form")
  }

  submitForm() {
    const form = this.form
    if (form) {
      form.requestSubmit()
    }
  }

  search(event) {
    const value = event.target.value.trim()
    
    // Update clear button visibility
    this.updateClearButton()

    // Clear existing timeout
    if (this.timeout) {
      clearTimeout(this.timeout)
    }

    // Submit if meets minimum length requirement
    if (value.length >= this.minLengthValue) {
      this.timeout = setTimeout(() => {
        this.submitForm()
      }, this.delayValue)
    } else if (value.length === 0) {
      // Submit immediately when cleared
      this.submitForm()
    }
  }

  clear(event) {
    event.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
      this.inputTarget.focus()
      this.updateClearButton()
      this.submitForm()
    }
  }

  submit(event) {
    // Allow Enter key to submit immediately
    if (event.key === "Enter") {
      if (this.timeout) {
        clearTimeout(this.timeout)
      }
      this.submitForm()
    }
  }

  updateClearButton() {
    if (this.hasClearButtonTarget) {
      const hasValue = this.hasInputTarget && this.inputTarget.value.trim().length > 0
      this.clearButtonTarget.classList.toggle("hidden", !hasValue)
    }
  }
}

