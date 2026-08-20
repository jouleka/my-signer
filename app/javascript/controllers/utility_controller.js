import { Controller } from "@hotwired/stimulus"

// Generic utility controller for common DOM actions
// Usage examples:
//   <button data-controller="utility" data-action="click->utility#reload">Reload</button>
//   <button data-controller="utility" data-action="click->utility#remove" data-utility-target-value="banner-id">Dismiss</button>
//   <button data-controller="utility" data-action="click->utility#removeSelf">Remove me</button>

export default class extends Controller {
  static values = {
    target: String, // ID of element to target
    url: String     // URL for redirects
  }

  // Reload the current page
  reload(event) {
    event?.preventDefault()
    window.location.reload()
  }

  // Remove an element by ID
  remove(event) {
    event?.preventDefault()
    if (this.hasTargetValue) {
      const element = document.getElementById(this.targetValue)
      if (element) {
        element.remove()
      }
    }
  }

  // Remove the controller's own element or closest removable parent
  removeSelf(event) {
    event?.preventDefault()
    const target = event?.currentTarget?.closest("[data-removable]") || this.element
    target.remove()
  }

  // Clear a sibling input and focus it (for search clear buttons)
  clearInput(event) {
    event?.preventDefault()
    const input = event.currentTarget.previousElementSibling
    if (input && (input.tagName === "INPUT" || input.tagName === "TEXTAREA")) {
      input.value = ""
      input.focus()
      // Trigger input event in case there are listeners
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  // Redirect to a URL
  redirect(event) {
    event?.preventDefault()
    if (this.hasUrlValue) {
      window.location.href = this.urlValue
    }
  }

  // Clear the innerHTML of an element by ID (useful for clearing turbo frames)
  clearElement(event) {
    event?.preventDefault()
    if (this.hasTargetValue) {
      const element = document.getElementById(this.targetValue)
      if (element) {
        element.innerHTML = ""
      }
    }
  }
}
