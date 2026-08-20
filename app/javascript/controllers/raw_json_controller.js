import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    title: { type: String, default: "Apple Payload" },
    content: String
  }

  connect() {
    this.modal = document.getElementById("raw-json-modal")
    if (!this.modal) return
    this.titleElement = this.modal.querySelector('[data-raw-json-element="title"]')
    this.codeElement = this.modal.querySelector('[data-raw-json-element="code"]')
    this.copyButton = this.modal.querySelector('[data-raw-json-element="copy"]')
    if (this.copyButton) {
      this.copyButton.addEventListener("click", () => this.copy())
    }
    this.modal.addEventListener("close", () => this.resetCopyButton())
  }

  show(event) {
    event.preventDefault()
    if (!this.modal || !this.codeElement || !this.titleElement) return

    const pretty = this.#prettyPrint(this.contentValue)
    this.codeElement.textContent = pretty
    this.titleElement.textContent = this.titleValue
    this.copyContent = pretty
    this.resetCopyButton()

    if (typeof this.modal.showModal === "function") {
      this.modal.showModal()
    }
  }

  async copy() {
    if (!this.copyContent || !navigator.clipboard) return
    try {
      await navigator.clipboard.writeText(this.copyContent)
      if (this.copyButton) {
        this.copyButton.textContent = "Copied!"
        this.copyButton.classList.remove("btn-ghost", "btn-error")
        this.copyButton.classList.add("btn-success")
      }
    } catch (e) {
      if (this.copyButton) {
        this.copyButton.textContent = "Copy failed"
        this.copyButton.classList.remove("btn-ghost", "btn-success")
        this.copyButton.classList.add("btn-error")
      }
    }
    setTimeout(() => this.resetCopyButton(), 1600)
  }

  resetCopyButton() {
    if (!this.copyButton) return
    this.copyButton.textContent = "Copy JSON"
    this.copyButton.classList.remove("btn-success", "btn-error")
    this.copyButton.classList.add("btn-ghost")
  }

  #prettyPrint(raw) {
    if (!raw) return ""
    try {
      const parsed = JSON.parse(raw)
      return JSON.stringify(parsed, null, 2)
    } catch (e) {
      const normalized = this.#normalizeHashrocket(raw)
      if (normalized) {
        try {
          const parsed = JSON.parse(normalized)
          return JSON.stringify(parsed, null, 2)
        } catch (_) {
          return normalized
        }
      }
      return raw
    }
  }

  #normalizeHashrocket(raw) {
    if (typeof raw !== "string" || !raw.includes("=>")) return null
    let normalized = raw
    // Replace Ruby hash rockets with JSON colons
    normalized = normalized.replace(/=>/g, ":")
    // Replace Ruby nil/true/false if present
    normalized = normalized.replace(/\bnil\b/g, "null")
    normalized = normalized.replace(/\btrue\b/g, "true")
    normalized = normalized.replace(/\bfalse\b/g, "false")
    return normalized
  }
}
