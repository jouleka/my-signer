import { Controller } from "@hotwired/stimulus"

// Custom confirmation dialog that replaces the native browser confirm()
// Used globally via Turbo.config.forms.confirm and for manual invocations
//
// Usage (automatic via Turbo):
//   <form data-turbo-confirm="Are you sure?">...</form>
//
// Usage (manual):
//   <button data-controller="confirm-dialog"
//           data-confirm-dialog-title-value="Skip setup?"
//           data-confirm-dialog-message-value="You can finish later."
//           data-confirm-dialog-confirm-text-value="Continue"
//           data-confirm-dialog-variant-value="warning"
//           data-action="click->confirm-dialog#show">

export default class extends Controller {
  static values = {
    title: { type: String, default: "" },
    message: { type: String, default: "" },
    confirmText: { type: String, default: "Continue" },
    cancelText: { type: String, default: "Cancel" },
    variant: { type: String, default: "warning" }, // warning, danger, info
    formAction: { type: String, default: "" }
  }

  show(event) {
    event.preventDefault()
    event.stopPropagation()

    const form = this.element.closest("form") || this.element.querySelector("form")

    showConfirmDialog({
      title: this.titleValue,
      message: this.messageValue,
      confirmText: this.confirmTextValue,
      cancelText: this.cancelTextValue,
      variant: this.variantValue
    }).then((confirmed) => {
      if (confirmed && form) {
        // Remove the turbo-confirm so it doesn't loop
        const originalConfirm = form.dataset.turboConfirm
        delete form.dataset.turboConfirm
        form.requestSubmit()
        if (originalConfirm) form.dataset.turboConfirm = originalConfirm
      }
    })
  }
}

// ─── Global confirm dialog function ───────────────────────────────
// Returns a Promise<boolean>

export function showConfirmDialog({
  title = "Are you sure?",
  message = "",
  confirmText = "Continue",
  cancelText = "Cancel",
  variant = "warning" // warning | danger | info
} = {}) {
  return new Promise((resolve) => {
    // Remove any existing confirm dialog
    const existing = document.getElementById("global-confirm-dialog")
    if (existing) existing.remove()

    const iconMap = {
      warning: { icon: "fa-solid fa-triangle-exclamation", color: "text-warning", bg: "bg-warning/10", border: "border-warning/20", btnClass: "btn-warning" },
      danger:  { icon: "fa-solid fa-trash-can",             color: "text-error",   bg: "bg-error/10",   border: "border-error/20",   btnClass: "btn-error" },
      info:    { icon: "fa-solid fa-circle-info",            color: "text-info",    bg: "bg-info/10",    border: "border-info/20",    btnClass: "btn-primary" }
    }
    const style = iconMap[variant] || iconMap.warning

    // Build dialog DOM safely without innerHTML
    const dialog = document.createElement("dialog")
    dialog.id = "global-confirm-dialog"
    dialog.className = "modal modal-bottom sm:modal-middle"

    const modalBox = document.createElement("div")
    modalBox.className = "modal-box max-w-sm p-0 overflow-hidden"

    // Content area
    const content = document.createElement("div")
    content.className = "p-6 text-center"

    const iconWrap = document.createElement("div")
    iconWrap.className = `inline-flex items-center justify-center w-14 h-14 rounded-full ${style.bg} ${style.border} border-2 mb-4`
    const icon = document.createElement("i")
    icon.className = `${style.icon} text-xl ${style.color}`
    iconWrap.appendChild(icon)
    content.appendChild(iconWrap)

    if (title) {
      const h3 = document.createElement("h3")
      h3.className = "font-bold text-lg mb-2"
      h3.textContent = title
      content.appendChild(h3)
    }

    if (message) {
      const p = document.createElement("p")
      p.className = "text-sm text-base-content/70 leading-relaxed"
      p.textContent = message
      content.appendChild(p)
    }

    modalBox.appendChild(content)

    // Button row
    const btnRow = document.createElement("div")
    btnRow.className = "flex border-t border-base-300"

    const cancelBtn = document.createElement("button")
    cancelBtn.type = "button"
    cancelBtn.className = "flex-1 py-3.5 text-sm font-medium hover:bg-base-200/50 transition-colors border-r border-base-300"
    cancelBtn.textContent = cancelText

    const confirmBtn = document.createElement("button")
    confirmBtn.type = "button"
    confirmBtn.className = `flex-1 py-3.5 text-sm font-bold ${style.color} hover:bg-base-200/50 transition-colors`
    confirmBtn.textContent = confirmText

    btnRow.appendChild(cancelBtn)
    btnRow.appendChild(confirmBtn)
    modalBox.appendChild(btnRow)

    dialog.appendChild(modalBox)

    // Backdrop
    const backdropForm = document.createElement("form")
    backdropForm.method = "dialog"
    backdropForm.className = "modal-backdrop"
    const backdropBtn = document.createElement("button")
    backdropBtn.textContent = "close"
    backdropForm.appendChild(backdropBtn)
    dialog.appendChild(backdropForm)

    document.body.appendChild(dialog)

    const cleanup = (result) => {
      dialog.close()
      dialog.remove()
      resolve(result)
    }

    cancelBtn.addEventListener("click", () => cleanup(false))
    confirmBtn.addEventListener("click", () => cleanup(true))
    backdropBtn.addEventListener("click", () => cleanup(false))
    dialog.addEventListener("cancel", () => cleanup(false)) // ESC key

    dialog.showModal()
  })
}

// ─── Override Turbo's native confirm ──────────────────────────────
// This replaces ALL data-turbo-confirm across the app

document.addEventListener("turbo:load", installTurboConfirm, { once: true })
document.addEventListener("DOMContentLoaded", installTurboConfirm, { once: true })

function installTurboConfirm() {
  if (typeof Turbo === "undefined") return

  const confirmMethod = (message, _element) => {
    return showConfirmDialog({
      title: "Just a moment",
      message: message,
      confirmText: "Yes, continue",
      cancelText: "Go back",
      variant: "warning"
    })
  }

  // Turbo 8+: Turbo.config.forms.confirm. The top-level setConfirmMethod
  // is deprecated and emits a console warning on every form render.
  if (Turbo.config?.forms) {
    Turbo.config.forms.confirm = confirmMethod
  } else if (typeof Turbo.setConfirmMethod === "function") {
    Turbo.setConfirmMethod(confirmMethod)
  }
}
