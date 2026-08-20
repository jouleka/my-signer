import { Controller } from "@hotwired/stimulus"

// Controller for the settings page functionality
// Handles: modal auto-open, revoke token modal, password field toggle

export default class extends Controller {
  static values = {
    openModal: String // Modal ID to open on connect (server-side controlled)
  }

  static targets = [
    "emailInput",
    "passwordContainer",
    "passwordInput",
    "revokeTokenName",
    "revokeTokenForm",
    "themeToggle"
  ]

  connect() {
    // Auto-open modal if specified by server
    if (this.hasOpenModalValue && this.openModalValue) {
      this.openModalById(this.openModalValue)
    }

    // Initialize password field visibility
    this.togglePasswordField()
  }

  // Open a modal by ID
  openModalById(modalId) {
    const modal = document.getElementById(modalId)
    if (modal && typeof modal.showModal === "function" && !modal.open) {
      modal.showModal()
    }
  }

  // Toggle password field visibility based on email change
  togglePasswordField() {
    if (!this.hasEmailInputTarget || !this.hasPasswordContainerTarget || !this.hasPasswordInputTarget) {
      return
    }

    const emailInput = this.emailInputTarget
    const passwordContainer = this.passwordContainerTarget
    const passwordInput = this.passwordInputTarget

    const originalEmail = emailInput.dataset.originalEmail
    const forceVisible = passwordContainer.dataset.forceVisible === "true"
    const shouldShow = forceVisible || (originalEmail && emailInput.value !== originalEmail)

    passwordContainer.classList.toggle("hidden", !shouldShow)
    passwordContainer.dataset.forceVisible = shouldShow
    passwordInput.required = shouldShow

    if (!shouldShow && !forceVisible) {
      passwordInput.value = ""
    }
  }

  // Called when email input changes
  emailChanged() {
    this.togglePasswordField()
  }

  // Show the revoke token confirmation modal
  showRevokeTokenModal(event) {
    const button = event.currentTarget
    const tokenId = button.dataset.tokenId
    const tokenName = button.dataset.tokenName
    const orgId = button.dataset.orgId

    if (this.hasRevokeTokenNameTarget) {
      this.revokeTokenNameTarget.textContent = tokenName
    }

    if (this.hasRevokeTokenFormTarget) {
      this.revokeTokenFormTarget.action = `/organizations/${orgId}/api_tokens/${tokenId}`
    }

    const modal = document.getElementById("revoke_token_modal_settings")
    if (modal && typeof modal.showModal === "function") {
      modal.showModal()
    }
  }

  // Toggle theme via the hidden checkbox
  toggleTheme() {
    if (this.hasThemeToggleTarget) {
      this.themeToggleTarget.click()
    }
  }
}
