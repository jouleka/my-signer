import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "content"]

  connect() {
    this.close()
    this.boundCloseOthers = this.closeOthers.bind(this)
    window.addEventListener("dropdown:open", this.boundCloseOthers)
  }

  disconnect() {
    window.removeEventListener("dropdown:open", this.boundCloseOthers)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    // Close other dropdowns first
    window.dispatchEvent(new CustomEvent("dropdown:open", { detail: { controller: this } }))

    this.isOpen = true
    this.contentTarget.classList.remove("hidden")
    this.updatePosition()

    // Close on click outside
    this.clickOutsideHandler = (event) => {
      if (!this.element.contains(event.target) && !this.contentTarget.contains(event.target)) {
        this.close()
      }
    }
    
    // Close on scroll/resize to avoid detached menu
    this.resizeHandler = () => this.close()

    document.addEventListener("click", this.clickOutsideHandler)
    window.addEventListener("resize", this.resizeHandler)
    window.addEventListener("scroll", this.resizeHandler, true)
  }

  close() {
    this.isOpen = false
    if (this.hasContentTarget) {
      this.contentTarget.classList.add("hidden")
      // Reset styles
      this.contentTarget.style.position = ""
      this.contentTarget.style.top = ""
      this.contentTarget.style.left = ""
      this.contentTarget.style.width = ""
      this.contentTarget.style.zIndex = ""
    }

    if (this.clickOutsideHandler) {
      document.removeEventListener("click", this.clickOutsideHandler)
      window.removeEventListener("resize", this.resizeHandler)
      window.removeEventListener("scroll", this.resizeHandler, true)
    }
  }

  closeOthers(event) {
    if (event.detail.controller !== this && this.isOpen) {
      this.close()
    }
  }

  updatePosition() {
    const buttonRect = this.buttonTarget.getBoundingClientRect()
    
    // Default to bottom-end (aligned right, below button)
    const width = 208 // w-52 = 13rem = 208px
    let top = buttonRect.bottom + 4
    let left = buttonRect.right - width

    // Check if it fits on the left, otherwise align left
    if (left < 0) {
      left = buttonRect.left
    }

    this.contentTarget.style.position = "fixed"
    this.contentTarget.style.top = `${top}px`
    this.contentTarget.style.left = `${left}px`
    this.contentTarget.style.width = "13rem"
    this.contentTarget.style.zIndex = "9999"
  }
}
