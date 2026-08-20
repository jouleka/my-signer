import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "input", "item"]
  static values = { openClass: String }

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  open(event) {
    event?.preventDefault()
    this.containerTarget.classList.add(this.openClass)
    requestAnimationFrame(() => {
      this.inputTarget?.focus()
    })
  }

  close(event) {
    event?.preventDefault()
    this.containerTarget.classList.remove(this.openClass)
  }

  execute() {
    // Allow navigation to start before closing the palette.
    setTimeout(() => this.close(), 0)
  }

  filter(event) {
    const query = event.target.value.trim().toLowerCase()
    this.itemTargets.forEach((item) => {
      const label = item.dataset.commandPaletteLabel || ""
      item.classList.toggle("hidden", Boolean(query) && !label.includes(query))
    })
  }

  handleKeydown(event) {
    const key = event.key.toLowerCase()

    if ((event.metaKey || event.ctrlKey) && key === "k") {
      event.preventDefault()
      this.open()
      return
    }

    if (!this.isOpen) return

    if (key === "escape") {
      this.close(event)
    }
  }


  get isOpen() {
    return this.containerTarget.classList.contains(this.openClass)
  }

  get openClass() {
    return this.openClassValue || "modal-open"
  }
}
