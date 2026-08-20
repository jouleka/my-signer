import { Controller } from "@hotwired/stimulus"

// Generic modal controller for opening/closing HTML dialog elements
// Usage:
//   <button data-controller="modal" data-action="click->modal#open" data-modal-target-value="my_modal_id">Open</button>
//   <button data-controller="modal" data-action="click->modal#close" data-modal-target-value="my_modal_id">Close</button>
//   <button data-controller="modal" data-action="click->modal#switch" data-modal-target-value="current_modal" data-modal-open-value="new_modal">Switch</button>
//   <dialog id="my_modal_id">...</dialog>

export default class extends Controller {
  static values = {
    target: String, // The ID of the dialog element to control (for close/switch)
    open: String    // The ID of the dialog to open (for switch operation)
  }

  open(event) {
    event.preventDefault()
    const modal = this.findModal()
    if (modal && typeof modal.showModal === "function" && !modal.open) {
      modal.showModal()
    }
  }

  close(event) {
    event.preventDefault()
    const modal = this.findModal()
    if (modal && typeof modal.close === "function") {
      modal.close()
    }
  }

  // Close current modal and open another
  switch(event) {
    event.preventDefault()
    // Close the current modal
    const currentModal = this.findModal()
    if (currentModal && typeof currentModal.close === "function") {
      currentModal.close()
    }
    // Open the new modal
    if (this.hasOpenValue) {
      const newModal = document.getElementById(this.openValue)
      if (newModal && typeof newModal.showModal === "function" && !newModal.open) {
        newModal.showModal()
      }
    }
  }

  findModal() {
    if (this.hasTargetValue) {
      return document.getElementById(this.targetValue)
    }
    // Fallback: find closest dialog parent
    return this.element.closest("dialog")
  }
}
