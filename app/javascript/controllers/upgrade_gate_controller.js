import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    blocked: Boolean,
    prompt: Object,
    closeNearestDialog: Boolean
  }

  intercept(event) {
    if (!this.blockedValue) return

    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation?.()

    const presentPrompt = () => {
      document.dispatchEvent(new CustomEvent("mysigner:upgrade-prompt", {
        detail: {
          ...(this.promptValue || {}),
          sourceElement: this.closeNearestDialogValue ? null : this.element
        }
      }))
    }

    if (this.closeNearestDialogValue) {
      const dialog = this.element.closest("dialog")
      if (dialog && typeof dialog.close === "function" && dialog.open) {
        dialog.close()
      }
      requestAnimationFrame(presentPrompt)
      return
    }

    presentPrompt()
  }
}
