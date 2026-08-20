import { Controller } from "@hotwired/stimulus"

/*
 * Locale switcher + autosave for the What's New editor.
 *
 * Responsibilities:
 *   1. Show one editor panel at a time, picked by a <select>. Each panel
 *      represents one locale (base locale uses the template editor; every
 *      other locale uses a single translation textarea).
 *   2. Swap the on-the-right phone preview to match the active locale.
 *   3. Hide locale-specific action buttons that only make sense on the base
 *      locale (AI Rewrite, Translate to all).
 *   4. Autosave inputs via fetch — debounced while typing, flushed on blur,
 *      flushed when switching locales, flushed on page hide. Shows a small
 *      "Saving… / Saved / Unsaved" indicator in the action row.
 *
 * The server responds to autosave POSTs with `head :ok` (no redirect, no
 * render) so the page never navigates while the user is typing.
 */
export default class extends Controller {
  static targets = [
    "selector",
    "panel",
    "previewPanel",
    "baseForm",
    "translationForm",
    "translationTextarea",
    "translationCharCount",
    "translationPreview",
    "savingIndicator",
    "baseOnlyAction"
  ]
  static values = {
    active: String,
    baseLocale: String
  }

  connect() {
    this._autosaveTimer = null
    this._pendingForm = null
    this._pageHideHandler = () => this._flushSave()
    window.addEventListener("pagehide", this._pageHideHandler)
    this._applyActive()
  }

  disconnect() {
    if (this._autosaveTimer) clearTimeout(this._autosaveTimer)
    window.removeEventListener("pagehide", this._pageHideHandler)
  }

  // ── Locale switching ──

  switch(event) {
    const locale = event.target.value
    if (!locale || locale === this.activeValue) return
    // Flush any pending save for the locale we're leaving before switching.
    this._flushSave()
    this.activeValue = locale
  }

  activeValueChanged() {
    this._applyActive()
  }

  _applyActive() {
    const active = this.activeValue
    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.locale !== active)
    })
    this.previewPanelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.locale !== active)
    })
    const onBase = active === this.baseLocaleValue
    this.baseOnlyActionTargets.forEach(el => {
      el.classList.toggle("hidden", !onBase)
    })
  }

  // ── Autosave triggers ──

  // Any input in the active form schedules an autosave.
  scheduleAutosave(event) {
    const form = event.target.closest("form")
    if (!form) return
    this._pendingForm = form
    this._setSaving("unsaved")
    if (this._autosaveTimer) clearTimeout(this._autosaveTimer)
    this._autosaveTimer = setTimeout(() => this._save(), 900)
  }

  // Blur → save right away if dirty.
  flushOnBlur() {
    this._flushSave()
  }

  // Live-update the per-locale translation preview while the user types.
  updateTranslationPreview(event) {
    const textarea = event.target
    const locale = textarea.dataset.locale
    if (!locale) return
    const preview = this.translationPreviewTargets.find(el => el.dataset.locale === locale)
    if (preview) {
      const text = textarea.value
      preview.textContent = text || "Release notes will appear here..."
      preview.classList.toggle("opacity-30", !text)
      preview.classList.toggle("italic", !text)
    }
    const counter = this.translationCharCountTargets.find(el => el.dataset.locale === locale)
    if (counter) {
      const limit = parseInt(counter.dataset.limit || "0", 10)
      const len = textarea.value.length
      counter.textContent = `${len}/${limit}`
      counter.classList.remove("text-error", "text-warning", "text-base-content/40")
      if (limit > 0 && len > limit) counter.classList.add("text-error")
      else if (limit > 0 && len > limit * 0.9) counter.classList.add("text-warning")
      else counter.classList.add("text-base-content/40")
    }
  }

  // ── Save implementation ──

  _flushSave() {
    if (!this._autosaveTimer) return
    clearTimeout(this._autosaveTimer)
    this._autosaveTimer = null
    this._save()
  }

  async _save() {
    const form = this._pendingForm
    this._pendingForm = null
    this._autosaveTimer = null
    if (!form) return

    this._setSaving("saving")

    try {
      const formData = new FormData(form)
      // Rails form_with's _method override needs to be honored by fetch.
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
      } else {
        this._setSaving("error")
      }
    } catch (_e) {
      this._setSaving("error")
    }
  }

  // Renders the saving indicator using DOM APIs (not innerHTML) so static text
  // stays static — no XSS surface.
  _setSaving(state) {
    if (!this.hasSavingIndicatorTarget) return
    const el = this.savingIndicatorTarget
    // Clear previous content/class state.
    while (el.firstChild) el.removeChild(el.firstChild)
    const baseClasses = "inline-flex items-center gap-1.5 text-[0.625rem]"

    const textFor = { saving: "Saving…", saved: "Saved", unsaved: "Unsaved", error: "Failed to save" }[state] || ""
    const iconClassFor = {
      saving: "loading loading-spinner loading-xs",
      saved: "fa-regular fa-circle-check",
      unsaved: "fa-regular fa-clock",
      error: "fa-solid fa-triangle-exclamation"
    }[state]
    const colorClassFor = {
      saving: "text-base-content/50",
      saved: "text-success/80",
      unsaved: "text-base-content/40",
      error: "text-error"
    }[state] || "text-base-content/40"

    el.className = `${baseClasses} ${colorClassFor}`

    if (iconClassFor) {
      const icon = document.createElement(state === "saving" ? "span" : "i")
      iconClassFor.split(" ").filter(Boolean).forEach(c => icon.classList.add(c))
      el.appendChild(icon)
    }
    const textNode = document.createElement("span")
    textNode.textContent = textFor
    el.appendChild(textNode)
  }
}
