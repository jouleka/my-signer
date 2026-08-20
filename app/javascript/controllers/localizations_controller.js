import { Controller } from "@hotwired/stimulus"

// Localizations controller for managing dynamic localization entries in forms
// Used in app store release forms to add/remove locale-specific content
export default class extends Controller {
  static targets = ["container", "template", "entry", "addButton", "localeSelect"]

  static values = {
    maxEntries: { type: Number, default: 50 },
    locales: { type: Array, default: [] }
  }

  connect() {
    this.updateAddButtonState()
    this.updateAvailableLocales()
  }

  add(event) {
    event.preventDefault()

    if (this.entryTargets.length >= this.maxEntriesValue) {
      this.showNotification("Maximum number of localizations reached", "error")
      return
    }

    const template = this.templateTarget.content.cloneNode(true)
    const entry = template.querySelector("[data-localizations-target='entry']")

    // Generate unique index for form field names
    const index = Date.now()
    this.updateFieldNames(entry, index)

    // Insert before add button
    this.containerTarget.insertBefore(entry, this.addButtonTarget)

    this.updateAddButtonState()
    this.updateAvailableLocales()

    // Focus the first input in the new entry
    const firstInput = entry.querySelector("input, select, textarea")
    if (firstInput) {
      firstInput.focus()
    }
  }

  remove(event) {
    event.preventDefault()

    const entry = event.target.closest("[data-localizations-target='entry']")
    if (entry) {
      // Add a fade-out animation
      entry.style.opacity = "0"
      entry.style.transform = "translateX(-10px)"
      entry.style.transition = "opacity 0.2s, transform 0.2s"

      setTimeout(() => {
        entry.remove()
        this.updateAddButtonState()
        this.updateAvailableLocales()
      }, 200)
    }
  }

  updateFieldNames(entry, index) {
    // Update all field names to use the new index
    entry.querySelectorAll("[name]").forEach((field) => {
      const name = field.getAttribute("name")
      if (name) {
        field.setAttribute("name", name.replace("__INDEX__", index))
      }
    })

    // Update IDs as well for label associations
    entry.querySelectorAll("[id]").forEach((element) => {
      const id = element.getAttribute("id")
      if (id) {
        element.setAttribute("id", id.replace("__INDEX__", index))
      }
    })

    // Update labels' for attributes
    entry.querySelectorAll("label[for]").forEach((label) => {
      const forAttr = label.getAttribute("for")
      if (forAttr) {
        label.setAttribute("for", forAttr.replace("__INDEX__", index))
      }
    })
  }

  updateAddButtonState() {
    if (this.hasAddButtonTarget) {
      const disabled = this.entryTargets.length >= this.maxEntriesValue
      this.addButtonTarget.disabled = disabled

      if (disabled) {
        this.addButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
      } else {
        this.addButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
      }
    }
  }

  updateAvailableLocales() {
    // Get all currently selected locales
    const selectedLocales = new Set()
    this.entryTargets.forEach((entry) => {
      const localeSelect = entry.querySelector("[data-locale-select]")
      if (localeSelect && localeSelect.value) {
        selectedLocales.add(localeSelect.value)
      }
    })

    // Update each locale select to disable already-selected locales
    this.entryTargets.forEach((entry) => {
      const localeSelect = entry.querySelector("[data-locale-select]")
      if (localeSelect) {
        const currentValue = localeSelect.value
        Array.from(localeSelect.options).forEach((option) => {
          if (option.value && option.value !== currentValue) {
            option.disabled = selectedLocales.has(option.value)
          }
        })
      }
    })
  }

  onLocaleChange() {
    this.updateAvailableLocales()
  }

  showNotification(message, type = "info") {
    // Simple notification - can be enhanced with a toast system
    const notification = document.createElement("div")
    notification.className = `fixed bottom-4 right-4 px-4 py-2 rounded-lg shadow-lg z-50 ${
      type === "error" ? "bg-red-500 text-white" : "bg-blue-500 text-white"
    }`
    notification.textContent = message
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.style.opacity = "0"
      notification.style.transition = "opacity 0.3s"
      setTimeout(() => notification.remove(), 300)
    }, 3000)
  }

  // Expand/collapse localization entry details
  toggleExpand(event) {
    event.preventDefault()
    const entry = event.target.closest("[data-localizations-target='entry']")
    if (entry) {
      const details = entry.querySelector("[data-details]")
      const icon = event.target.querySelector("[data-expand-icon]")

      if (details) {
        details.classList.toggle("hidden")
        if (icon) {
          icon.classList.toggle("rotate-180")
        }
      }
    }
  }
}
