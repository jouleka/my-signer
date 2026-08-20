import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = []

  connect() {
    const savedTheme = localStorage.getItem("theme") || "my-signer-dark"
    this.setTheme(savedTheme)
    
    this.element.checked = savedTheme === "my-signer-dark"
  }

  toggle() {
    const currentTheme = document.documentElement.getAttribute("data-theme")
    const newTheme = currentTheme === "my-signer-dark" ? "my-signer-light" : "my-signer-dark"
    
    this.setTheme(newTheme)
    localStorage.setItem("theme", newTheme)
    
    // Sync all theme toggles on the page
    document.querySelectorAll('.theme-controller').forEach(toggle => {
      toggle.checked = newTheme === "my-signer-dark"
    })
  }

  setTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme)
  }
}

