import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropZone", "fileInput", "form"]
  static values = { url: String }

  browse() {
    if (this.hasFileInputTarget) {
      this.fileInputTarget.click()
    }
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.classList.add("border-primary", "bg-primary/10")
    }
  }

  dragLeave(event) {
    if (event.relatedTarget && this.hasDropZoneTarget && this.dropZoneTarget.contains(event.relatedTarget)) return
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.classList.remove("border-primary", "bg-primary/10")
    }
  }

  drop(event) {
    event.preventDefault()
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.classList.remove("border-primary", "bg-primary/10")
    }

    const files = Array.from(event.dataTransfer.files).filter(f =>
      f.type === "image/png" || f.type === "image/jpeg"
    )
    if (files.length === 0) return

    this.uploadFiles(files)
  }

  filesSelected(event) {
    const files = Array.from(event.target.files).filter(f =>
      f.type === "image/png" || f.type === "image/jpeg"
    )
    if (files.length === 0) return

    this.uploadFiles(files)
  }

  uploadFiles(files) {
    if (!this.hasFormTarget) return

    // Set the files on the file input using DataTransfer
    const dataTransfer = new DataTransfer()
    files.forEach(f => dataTransfer.items.add(f))
    if (this.hasFileInputTarget) {
      this.fileInputTarget.files = dataTransfer.files
    }

    // Submit the form
    this.formTarget.requestSubmit()
  }
}
