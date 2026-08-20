import { Controller } from "@hotwired/stimulus"

// Opens an existing <dialog> element by id when the controller's element
// is clicked. Replaces inline onclick="document.getElementById('x')?.showModal()"
// handlers that were being blocked under the production CSP.
//
// Usage:
//   <button data-controller="dialog-open"
//           data-dialog-open-target-id-value="asc-add-cred-modal"
//           data-action="click->dialog-open#open">Connect Apple</button>
//   <dialog id="asc-add-cred-modal">…</dialog>
export default class extends Controller {
  static values = { targetId: String }

  open(event) {
    event.preventDefault()
    const dialog = document.getElementById(this.targetIdValue)
    if (dialog && typeof dialog.showModal === "function") {
      dialog.showModal()
    }
  }
}
