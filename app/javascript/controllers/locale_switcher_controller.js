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
 *      flushed before navigation and actions. Shows a small
 *      "Saving… / Saved / Unsaved" indicator in the action row.
 *
 * Saves return JSON with the note's status and review state. Failed drafts
 * stay in the queue until corrected or retried.
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
    "baseOnlyAction", "approvedBanner", "reviewReminder", "noteStatus", "applyButton"
  ]
  static values = {
    active: String,
    baseLocale: String
  }

  connect() {
    this._pendingForms = new Map()
    this._revision = 0
    this._visitHandler = async event => {
      if (!this._pendingForms.size) return
      event.preventDefault()
      if (await this.flushSave()) window.Turbo.visit(event.detail.url)
    }
    this._submitHandler = async event => {
      if (!this._pendingForms.size) return
      event.preventDefault()
      event.stopImmediatePropagation()
      const { target, submitter } = event
      const isEditor = [...this.baseFormTargets, ...this.translationFormTargets].includes(target)
      if (await this.flushSave() && !isEditor) target.requestSubmit(submitter)
    }
    this._submitEndHandler = async event => {
      if (event.detail.success) return
      let detail = "Please try again."
      try { detail = (await event.detail.fetchResponse.response.clone().json()).errors?.[0] || detail } catch {}
      this._setSaving("error", detail)
    }
    this.element.addEventListener("turbo:submit-end", this._submitEndHandler)
    this._unloadHandler = event => {
      if (!this._pendingForms.size) return
      event.preventDefault()
      event.returnValue = ""
    }
    document.addEventListener("turbo:before-visit", this._visitHandler)
    document.addEventListener("submit", this._submitHandler, true)
    window.addEventListener("beforeunload", this._unloadHandler)
    this._applyActive()
  }

  disconnect() {
    clearTimeout(this._autosaveTimer)
    document.removeEventListener("turbo:before-visit", this._visitHandler)
    document.removeEventListener("submit", this._submitHandler, true)
    this.element.removeEventListener("turbo:submit-end", this._submitEndHandler)
    window.removeEventListener("beforeunload", this._unloadHandler)
  }

  // ── Locale switching ──

  switch(event) {
    const locale = event.target.value
    if (!locale || locale === this.activeValue) return
    // Flush any pending save for the locale we're leaving before switching.
    this.flushSave()
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
    this._pendingForms.set(form, ++this._revision)
    this._setSaving("unsaved")
    if (this._autosaveTimer) clearTimeout(this._autosaveTimer)
    this._autosaveTimer = setTimeout(() => this.flushSave(), 500)
  }

  // Blur → save right away if dirty.
  flushOnBlur() {
    this.flushSave()
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
      const len = Array.from(textarea.value).length
      counter.textContent = `${len}/${limit}`
      counter.classList.remove("text-error", "text-warning", "text-base-content/40")
      if (limit > 0 && len > limit) counter.classList.add("text-error")
      else if (limit > 0 && len > limit * 0.9) counter.classList.add("text-warning")
      else counter.classList.add("text-base-content/40")
    }
  }

  // ── Save implementation ──

  // Serialize saves across version, base content and translations. A request
  // only clears the revision it sent; newer edits and failures stay pending.
  flushSave() {
    clearTimeout(this._autosaveTimer)
    if (this._saving) return this._saving
    if (!this._pendingForms.size) return Promise.resolve(true)
    this._saving = this._saveChanges().finally(() => { this._saving = null })
    return this._saving
  }

  async _saveChanges() {
    while (this._pendingForms.size) {
      const [form, revision] = this._pendingForms.entries().next().value
      this._setSaving("saving")
      try {
        const formData = new FormData(form)
        const method = (formData.get("_method") || form.method || "POST").toString().toUpperCase()
        formData.delete("_method")
        const response = await fetch(form.action, {
          method, body: formData,
          headers: { "Accept": "text/vnd.turbo-stream.html", "X-Requested-With": "XMLHttpRequest" },
          credentials: "same-origin"
        })
        if (!response.ok || response.redirected) {
          let detail = "Please try saving again."
          try { detail = (await response.json()).errors?.[0] || detail } catch {}
          throw new Error(detail)
        }
        const state = await response.json()
        if (this.hasNoteStatusTarget) this.noteStatusTarget.textContent = state.status === "draft" ? "Draft" : this.noteStatusTarget.textContent
        if (state.review_required && state.review_decision !== "rejected" && this.hasApprovedBannerTarget) {
          this.approvedBannerTarget.classList.add("hidden")
          this.reviewReminderTarget.classList.remove("hidden")
          if (this.hasApplyButtonTarget) this.applyButtonTarget.disabled = true
        }
        if (this._pendingForms.get(form) === revision) this._pendingForms.delete(form)
      } catch (error) {
        this._setSaving("error", error.message)
        return false
      }
    }
    this._setSaving("saved")
    return true
  }

  // Renders the saving indicator using DOM APIs (not innerHTML) so static text
  // stays static — no XSS surface.
  _setSaving(state, detail = null) {
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
    textNode.textContent = detail ? `${textFor} — ${detail}` : textFor
    el.appendChild(textNode)
  }
}
