import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "keystorePassword",
    "keyPassword", 
    "keyAlias",
    "fileInput",
    "dropZone",
    "filePreview",
    "fileName"
  ]

  connect() {
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.addEventListener("dragover", this.onDragOver.bind(this))
      this.dropZoneTarget.addEventListener("dragleave", this.onDragLeave.bind(this))
      this.dropZoneTarget.addEventListener("drop", this.onDrop.bind(this))
    }
  }

  toggleKeystorePassword(event) {
    this.togglePasswordField(this.keystorePasswordTarget, event.currentTarget)
  }

  toggleKeyPassword(event) {
    this.togglePasswordField(this.keyPasswordTarget, event.currentTarget)
  }

  togglePasswordField(input, button) {
    const icon = button.querySelector("i")
    if (input.type === "password") {
      input.type = "text"
      icon.classList.remove("fa-eye")
      icon.classList.add("fa-eye-slash")
    } else {
      input.type = "password"
      icon.classList.remove("fa-eye-slash")
      icon.classList.add("fa-eye")
    }
  }

  fillDefaultAlias() {
    if (this.hasKeyAliasTarget) {
      this.keyAliasTarget.value = "key0"
      this.keyAliasTarget.focus()
    }
  }

  updateFileName(event) {
    const file = event.target.files?.[0]
    if (file && this.hasFilePreviewTarget && this.hasFileNameTarget) {
      this.fileNameTarget.textContent = file.name
      this.filePreviewTarget.classList.remove("hidden")
    }
  }

  clearFile() {
    if (this.hasFileInputTarget) {
      this.fileInputTarget.value = ""
    }
    if (this.hasFilePreviewTarget) {
      this.filePreviewTarget.classList.add("hidden")
    }
  }

  onDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
    this.dropZoneTarget.classList.add("border-primary", "bg-primary/10")
  }

  onDragLeave(event) {
    if (event.relatedTarget && this.dropZoneTarget.contains(event.relatedTarget)) return
    this.dropZoneTarget.classList.remove("border-primary", "bg-primary/10")
  }

  onDrop(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.remove("border-primary", "bg-primary/10")
    
    const file = event.dataTransfer.files?.[0]
    if (!file) return

    const ext = file.name.toLowerCase()
    if (!ext.endsWith(".jks") && !ext.endsWith(".keystore")) {
      return
    }

    // Transfer file to file input
    const dataTransfer = new DataTransfer()
    dataTransfer.items.add(file)
    if (this.hasFileInputTarget) {
      this.fileInputTarget.files = dataTransfer.files
      this.fileInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }
}
