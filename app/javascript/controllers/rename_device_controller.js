import { Controller } from "@hotwired/stimulus"

// Controller for rename device modal functionality
// Usage:
//   <div data-controller="rename-device" data-rename-device-base-url-value="/organizations/1/apple_devices">
//     <button data-action="click->rename-device#showModal"
//             data-device-id="123"
//             data-device-name="My Device">Rename</button>
//     <dialog data-rename-device-target="modal">
//       <form data-rename-device-target="form">
//         <input data-rename-device-target="nameInput">
//       </form>
//       <button data-action="click->rename-device#closeModal">Cancel</button>
//     </dialog>
//   </div>

export default class extends Controller {
  static targets = ["modal", "form", "nameInput"]
  static values = {
    baseUrl: String
  }

  showModal(event) {
    event.preventDefault()
    const button = event.currentTarget
    const deviceId = button.dataset.deviceId
    const deviceName = button.dataset.deviceName

    if (this.hasFormTarget && this.hasBaseUrlValue) {
      this.formTarget.action = `${this.baseUrlValue}/${deviceId}`
    }

    if (this.hasNameInputTarget) {
      this.nameInputTarget.value = deviceName
    }

    if (this.hasModalTarget && typeof this.modalTarget.showModal === "function") {
      this.modalTarget.showModal()
      if (this.hasNameInputTarget) {
        this.nameInputTarget.focus()
        this.nameInputTarget.select()
      }
    }
  }

  closeModal(event) {
    event?.preventDefault()
    if (this.hasModalTarget && typeof this.modalTarget.close === "function") {
      this.modalTarget.close()
    }
  }
}
