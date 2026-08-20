import { Controller } from "@hotwired/stimulus"

// Controller for revoke token modal functionality
// Usage:
//   <div data-controller="revoke-token" data-revoke-token-base-url-value="/organizations/1/api_tokens">
//     <button data-action="click->revoke-token#showModal"
//             data-token-id="123"
//             data-token-name="My Token">Revoke</button>
//     <dialog data-revoke-token-target="modal">
//       <span data-revoke-token-target="tokenName"></span>
//       <form data-revoke-token-target="form">...</form>
//       <button data-action="click->revoke-token#closeModal">Cancel</button>
//     </dialog>
//   </div>

export default class extends Controller {
  static targets = ["modal", "tokenName", "form"]
  static values = {
    baseUrl: String
  }

  showModal(event) {
    event.preventDefault()
    const button = event.currentTarget
    const tokenId = button.dataset.tokenId
    const tokenName = button.dataset.tokenName

    if (this.hasTokenNameTarget) {
      this.tokenNameTarget.textContent = tokenName
    }

    if (this.hasFormTarget && this.hasBaseUrlValue) {
      this.formTarget.action = `${this.baseUrlValue}/${tokenId}`
    }

    if (this.hasModalTarget && typeof this.modalTarget.showModal === "function") {
      this.modalTarget.showModal()
    }
  }

  closeModal(event) {
    event?.preventDefault()
    if (this.hasModalTarget && typeof this.modalTarget.close === "function") {
      this.modalTarget.close()
    }
  }
}
