import { Controller } from "@hotwired/stimulus"

// Mobile navigation controller for documentation pages
// Handles sidebar drawer and mobile TOC toggle
export default class extends Controller {
  static targets = ["sidebar", "toc", "sidebarOverlay", "tocOverlay"]

  connect() {
    this.sidebarOpen = false
    this.tocOpen = false
  }

  toggleSidebar() {
    this.sidebarOpen = !this.sidebarOpen
    this.updateSidebar()
  }

  toggleToc() {
    this.tocOpen = !this.tocOpen
    this.updateToc()
  }

  closeSidebar() {
    this.sidebarOpen = false
    this.updateSidebar()
  }

  closeToc() {
    this.tocOpen = false
    this.updateToc()
  }

  updateSidebar() {
    if (this.hasSidebarTarget) {
      if (this.sidebarOpen) {
        this.sidebarTarget.classList.remove("translate-x-[-100%]")
        this.sidebarTarget.classList.add("translate-x-0")
        if (this.hasSidebarOverlayTarget) {
          this.sidebarOverlayTarget.classList.remove("hidden")
        }
        document.body.classList.add("overflow-hidden")
      } else {
        this.sidebarTarget.classList.add("translate-x-[-100%]")
        this.sidebarTarget.classList.remove("translate-x-0")
        if (this.hasSidebarOverlayTarget) {
          this.sidebarOverlayTarget.classList.add("hidden")
        }
        document.body.classList.remove("overflow-hidden")
      }
    }
  }

  updateToc() {
    if (this.hasTocTarget) {
      if (this.tocOpen) {
        this.tocTarget.classList.remove("translate-x-full")
        this.tocTarget.classList.add("translate-x-0")
        if (this.hasTocOverlayTarget) {
          this.tocOverlayTarget.classList.remove("hidden")
        }
        document.body.classList.add("overflow-hidden")
      } else {
        this.tocTarget.classList.add("translate-x-full")
        this.tocTarget.classList.remove("translate-x-0")
        if (this.hasTocOverlayTarget) {
          this.tocOverlayTarget.classList.add("hidden")
        }
        document.body.classList.remove("overflow-hidden")
      }
    }
  }
}
