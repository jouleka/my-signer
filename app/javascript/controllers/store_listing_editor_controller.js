import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "savingIndicator", "form"]

  connect() {
    this._revision = 0
    this._savedRevision = 0
    this._visitHandler = async event => {
      if (!this._dirty) return
      event.preventDefault()
      if (await this.flushSave()) window.Turbo.visit(event.detail.url)
    }
    this._submitHandler = async event => {
      if (event.target === this.formTarget) {
        event.preventDefault()
        this.flushSave()
      } else if (this._dirty) {
        event.preventDefault()
        event.stopImmediatePropagation()
        const { target, submitter } = event
        if (await this.flushSave()) target.requestSubmit(submitter)
      }
    }
    this._unloadHandler = event => {
      if (!this._dirty) return
      event.preventDefault()
      event.returnValue = ""
    }
    document.addEventListener("turbo:before-visit", this._visitHandler)
    document.addEventListener("submit", this._submitHandler, true)
    window.addEventListener("beforeunload", this._unloadHandler)
  }

  disconnect() {
    clearTimeout(this._autosaveTimer)
    clearTimeout(this._previewTimeout)
    document.removeEventListener("turbo:before-visit", this._visitHandler)
    document.removeEventListener("submit", this._submitHandler, true)
    window.removeEventListener("beforeunload", this._unloadHandler)
  }

  get _dirty() { return this._revision !== this._savedRevision }

  updatePreview() {
    clearTimeout(this._previewTimeout)
    this._previewTimeout = setTimeout(() => this._syncPreview(), 150)
  }

  scheduleAutosave() {
    this._revision++
    this._setSaving("unsaved")
    clearTimeout(this._autosaveTimer)
    this._autosaveTimer = setTimeout(() => this.flushSave(), 900)
  }

  flushOnBlur() { this.flushSave() }

  // One request at a time, including edits made while that request is running.
  // Navigation and store actions await the same promise; failed drafts stay put.
  flushSave() {
    clearTimeout(this._autosaveTimer)
    if (this._saving) return this._saving
    if (!this._dirty || !this.hasFormTarget) return Promise.resolve(true)
    this._saving = this._saveChanges().finally(() => { this._saving = null })
    return this._saving
  }

  async _saveChanges() {
    while (this._dirty) {
      const revision = this._revision
      this._setSaving("saving")
      try {
        const formData = new FormData(this.formTarget)
        formData.delete("_method")
        const response = await fetch(this.formTarget.action, {
          method: "PATCH",
          body: formData,
          headers: { "Accept": "text/vnd.turbo-stream.html", "X-Requested-With": "XMLHttpRequest" },
          credentials: "same-origin"
        })
        if (!response.ok || response.redirected) {
          let detail = "Please try saving again."
          try { detail = (await response.json()).errors?.[0] || detail } catch {}
          throw new Error(detail)
        }
        this._savedRevision = revision
      } catch (error) {
        this._setSaving("error", error.message)
        return false
      }
    }
    this._setSaving("saved")
    return true
  }

  // DOM-only rendering of the saving state — static strings, no XSS surface.
  // `detail` is optional — used to append a specific error message to the
  // generic "Failed to save" label so users can see WHY the save failed.
  _setSaving(state, detail = null) {
    if (!this.hasSavingIndicatorTarget) return
    const el = this.savingIndicatorTarget
    while (el.firstChild) el.removeChild(el.firstChild)
    const baseClasses = "inline-flex items-center gap-1.5 text-[0.625rem]"

    const text = { saving: "Saving…", saved: "Saved", unsaved: "Unsaved", error: "Failed to save" }[state] || ""
    const iconClass = {
      saving: "loading loading-spinner loading-xs",
      saved: "fa-regular fa-circle-check",
      unsaved: "fa-regular fa-clock",
      error: "fa-solid fa-triangle-exclamation"
    }[state]
    const colorClass = {
      saving: "text-base-content/50",
      saved: "text-success/80",
      unsaved: "text-base-content/40",
      error: "text-error"
    }[state] || "text-base-content/40"

    el.className = `${baseClasses} ${colorClass}`
    if (iconClass) {
      const icon = document.createElement(state === "saving" ? "span" : "i")
      iconClass.split(" ").filter(Boolean).forEach(c => icon.classList.add(c))
      el.appendChild(icon)
    }
    const textNode = document.createElement("span")
    textNode.textContent = detail ? `${text} — ${detail}` : text
    el.appendChild(textNode)
  }

  _syncPreview() {
    if (!this.hasPreviewTarget) return
    if (!this.hasFormTarget) return

    const form = this.formTarget

    const textFields = {
      "app-name": "store_listing[app_name]",
      "subtitle": "store_listing[subtitle]",
      "description": "store_listing[description]",
      "short-description": "store_listing[short_description]",
      "whats-new": "store_listing[whats_new]",
      "promotional-text": "store_listing[promotional_text]"
    }

    // Update plain text fields
    Object.entries(textFields).forEach(([key, name]) => {
      const input = form.querySelector(`[name='${name}']`)
      if (!input) return
      const previewEl = this.previewTarget.querySelector(`[data-preview-field="${key}"]`)
      if (!previewEl) return

      const value = input.value.trim()
      previewEl.textContent = value || this._placeholder(key)
      previewEl.classList.toggle("opacity-30", !value)
      previewEl.classList.toggle("italic", !value)
    })

    // Update keywords (rendered as badges)
    const keywordsInput = form.querySelector("[name='store_listing[keywords]']")
    const keywordsContainer = this.previewTarget.querySelector("[data-preview-field='keywords']")
    if (keywordsInput && keywordsContainer) {
      const value = keywordsInput.value.trim()
      keywordsContainer.textContent = ""
      if (value) {
        value.split(",").forEach(kw => {
          const trimmed = kw.trim()
          if (!trimmed) return
          const badge = document.createElement("span")
          badge.className = "badge badge-sm badge-outline"
          badge.textContent = trimmed
          keywordsContainer.appendChild(badge)
        })
      } else {
        const placeholder = document.createElement("span")
        placeholder.className = "opacity-30 italic text-xs"
        placeholder.textContent = "No keywords"
        keywordsContainer.appendChild(placeholder)
      }
    }
  }

  _placeholder(key) {
    const placeholders = {
      "app-name": "App Name",
      "subtitle": "Subtitle",
      "description": "App description will appear here...",
      "short-description": "Short description",
      "whats-new": "Release notes will appear here...",
      "promotional-text": "Promotional text"
    }
    return placeholders[key] || "Not set"
  }
}
