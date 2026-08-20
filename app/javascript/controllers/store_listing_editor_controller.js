import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "savingIndicator", "form"]

  connect() {
    this._autosaveTimer = null
    this._pageHideHandler = () => this._flushSave()
    window.addEventListener("pagehide", this._pageHideHandler)
  }

  disconnect() {
    if (this._autosaveTimer) clearTimeout(this._autosaveTimer)
    window.removeEventListener("pagehide", this._pageHideHandler)
  }

  updatePreview() {
    clearTimeout(this._previewTimeout)
    this._previewTimeout = setTimeout(() => {
      this._syncPreview()
    }, 150)
  }

  // ── Autosave (same pattern as locale_switcher on the What's New tab) ──
  scheduleAutosave() {
    this._setSaving("unsaved")
    if (this._autosaveTimer) clearTimeout(this._autosaveTimer)
    this._autosaveTimer = setTimeout(() => this._save(), 900)
  }

  flushOnBlur() {
    this._flushSave()
  }

  // Flush any pending autosave synchronously before another action (e.g. AI
  // Translate) submits its own request. Prevents in-progress edits from being
  // lost to the Turbo refresh that follows a translation job.
  flushBeforeAction() {
    this._flushSave()
  }

  _flushSave() {
    if (!this._autosaveTimer) return
    clearTimeout(this._autosaveTimer)
    this._autosaveTimer = null
    this._save()
  }

  async _save() {
    // Null the timer handle so a subsequent focusout doesn't trigger a
    // redundant second save (the handle stays truthy after setTimeout fires,
    // so without this flushOnBlur would re-invoke _save every blur).
    this._autosaveTimer = null
    if (!this.hasFormTarget) return
    const form = this.formTarget
    this._setSaving("saving")

    try {
      const formData = new FormData(form)
      const method = (formData.get("_method") || form.method || "POST").toString().toUpperCase()
      if (formData.has("_method")) formData.delete("_method")

      const response = await fetch(form.action, {
        method: method === "GET" ? "GET" : method,
        body: method === "GET" ? undefined : formData,
        headers: {
          "Accept": "text/vnd.turbo-stream.html, text/html;q=0.9",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (response.ok) {
        this._setSaving("saved")
        return
      }

      // 422 (validation failure) — read the JSON body to show the actual
      // error so the user knows WHY the save didn't stick. Without this,
      // one over-limit field on the page silently reverts every other edit.
      let errorMsg = null
      try {
        const data = await response.json()
        if (data && Array.isArray(data.errors) && data.errors.length) {
          errorMsg = data.errors[0]
        }
      } catch (_e) { /* response wasn't JSON */ }

      this._setSaving("error", errorMsg)
    } catch (_e) {
      this._setSaving("error")
    }
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
