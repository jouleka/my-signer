import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "helper"]
  static values = {
    extensions: String
  }

  connect() {
    this.boundDragOver = this.onDragOver.bind(this)
    this.boundDragLeave = this.onDragLeave.bind(this)
    this.boundDrop = this.onDrop.bind(this)

    this.element.addEventListener("dragover", this.boundDragOver)
    this.element.addEventListener("dragleave", this.boundDragLeave)
    this.element.addEventListener("drop", this.boundDrop)

    this.defaultHelperText = this.hasHelperTarget ? this.helperTarget.textContent.trim() : ""
    this.messageTimeout = null
  }

  disconnect() {
    this.element.removeEventListener("dragover", this.boundDragOver)
    this.element.removeEventListener("dragleave", this.boundDragLeave)
    this.element.removeEventListener("drop", this.boundDrop)
    this.clearMessageTimeout()
  }

  onDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
    this.highlight()
  }

  onDragLeave(event) {
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) return
    this.resetHighlight()
  }

  onDrop(event) {
    event.preventDefault()
    this.resetHighlight()

    const file = event.dataTransfer.files?.[0]
    if (!file) return

    if (!this.isAllowedExtension(file.name)) {
      this.showMessage(`Only ${this.allowedExtensions.join(", ")} files are allowed.`, true)
      return
    }

    const reader = new FileReader()
    reader.onload = (loadEvent) => {
      const result = loadEvent.target?.result
      if (typeof result === "string") {
        this.textareaTarget.value = result.trim()
        this.textareaTarget.dispatchEvent(new Event("input", { bubbles: true }))
        this.showMessage(`${file.name} loaded`, false)
      }
    }
    reader.readAsText(file)
  }

  highlight() {
    this.textareaTarget.classList.add("border-primary", "bg-base-200")
  }

  resetHighlight() {
    this.textareaTarget.classList.remove("border-primary", "bg-base-200")
  }

  isAllowedExtension(filename) {
    const lower = filename.toLowerCase()
    return this.allowedExtensions.some((ext) => lower.endsWith(ext))
  }

  get allowedExtensions() {
    const raw = this.hasExtensionsValue ? this.extensionsValue : ".p8"
    return raw
      .split(",")
      .map((ext) => ext.trim().toLowerCase())
      .filter(Boolean)
  }

  showMessage(text, isError) {
    if (!this.hasHelperTarget) return

    this.helperTarget.textContent = text
    this.helperTarget.classList.toggle("text-error", isError)
    this.helperTarget.classList.toggle("text-base-content/60", !isError)

    this.clearMessageTimeout()
    this.messageTimeout = setTimeout(() => {
      this.helperTarget.textContent = this.defaultHelperText
      this.helperTarget.classList.remove("text-error")
      this.helperTarget.classList.add("text-base-content/60")
    }, 4000)
  }

  clearMessageTimeout() {
    if (this.messageTimeout) {
      clearTimeout(this.messageTimeout)
      this.messageTimeout = null
    }
  }
}
