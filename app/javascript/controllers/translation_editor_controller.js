import { Controller } from "@hotwired/stimulus"

/*
 * Translation editor — gives each non-base locale the same structured layout
 * as the base template editor (colored NEW / IMPROVED / FIXED sections with
 * editable bullet inputs). Edits are serialized into a hidden <textarea> which
 * is the actual form field submitted to update_release_translation.
 *
 * The hidden textarea also doubles as the `translationTextarea` target of the
 * locale-switcher controller, so its live input events drive the per-locale
 * preview and the autosave debounce for free.
 */
export default class extends Controller {
  static targets = [
    "hiddenInput",
    "itemList",
    "heading",
    "templatePanel",
    "freeformPanel",
    "freeformInput"
  ]
  static values  = { locale: String }

  connect() {
    // Sync once on connect so the hidden textarea reflects the visible UI
    // state (safe even if server-side value is already correct).
    this._serialize(false)
  }

  // ── Mode switching (Template ⇄ Freeform) ──

  switchToTemplate(event) {
    if (event) event.preventDefault()
    if (this.hasTemplatePanelTarget) this.templatePanelTarget.classList.remove("hidden")
    if (this.hasFreeformPanelTarget) this.freeformPanelTarget.classList.add("hidden")
    this._setActiveTab("template")
  }

  switchToFreeform(event) {
    if (event) event.preventDefault()
    if (this.hasTemplatePanelTarget) this.templatePanelTarget.classList.add("hidden")
    if (this.hasFreeformPanelTarget) this.freeformPanelTarget.classList.remove("hidden")
    // Copy the currently-serialized structured text into the freeform textarea
    // so editing starts from the latest state.
    if (this.hasFreeformInputTarget && this.hasHiddenInputTarget) {
      this.freeformInputTarget.value = this.hiddenInputTarget.value
    }
    this._setActiveTab("freeform")
  }

  // Freeform is the source of truth while active — mirror its value into the
  // hidden textarea and notify upstream (preview + autosave).
  syncFromFreeform() {
    if (!this.hasFreeformInputTarget || !this.hasHiddenInputTarget) return
    this.hiddenInputTarget.value = this.freeformInputTarget.value
    this.hiddenInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  _setActiveTab(active) {
    // Only flip tabs inside THIS controller's scope (won't touch base-locale tabs).
    const tabs = this.element.querySelectorAll("[data-mode-tab]")
    tabs.forEach(tab => {
      const mode = tab.dataset.modeTab
      tab.classList.toggle("is-tab-active", mode === active)
      tab.classList.toggle("is-tab-inactive", mode !== active)
    })
  }

  addItem(event) {
    event.preventDefault()
    const idx = parseInt(event.params.listIndex, 10)
    const list = this.itemListTargets[idx]
    if (!list) return

    const row = this._buildItemRow()
    list.appendChild(row)
    row.querySelector("input").focus()
    this._serialize()
  }

  removeItem(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-bullet-item]")
    if (row) row.remove()
    this._serialize()
  }

  // Fired on `input` from any heading / item input via data-action.
  handleInput() {
    this._serialize()
  }

  // ── Private ──

  _serialize(dispatch = true) {
    const chunks = []
    this.itemListTargets.forEach((list, idx) => {
      const heading = (this.headingTargets[idx]?.value || "").trim()
      const items = Array.from(list.querySelectorAll("[data-bullet-item] input"))
        .map(i => i.value.trim())
        .filter(Boolean)

      // Only emit sections that have actual items. An empty heading with no
      // items is dropped (no phantom entries in the saved text).
      if (items.length === 0) return

      const lines = []
      if (heading) lines.push(heading)
      items.forEach(i => lines.push(`- ${i}`))
      chunks.push(lines.join("\n"))
    })

    const text = chunks.join("\n\n").trim()
    if (!this.hasHiddenInputTarget) return
    this.hiddenInputTarget.value = text

    if (dispatch) {
      // Let locale-switcher see the change → preview + char count + autosave.
      this.hiddenInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  // MUST MATCH UiHelper::INPUT — any drift will cause dynamically-added bullet
  // inputs to look different from server-rendered ones. Same pattern as
  // release_note_editor_controller.js.
  static INPUT_CLASSES = "block w-full text-sm leading-relaxed px-3 py-2 rounded-lg border border-base-content/[0.1] bg-base-content/[0.03] text-base-content/85 outline-none transition-[border-color,box-shadow,background] duration-150 hover:border-base-content/15 focus:border-primary/40 focus:bg-base-content/[0.05] focus:shadow-[0_0_0_3px_oklch(var(--color-primary)/0.08)]"

  _buildItemRow() {
    const row = document.createElement("div")
    row.className = "flex gap-2 items-center mb-2"
    row.dataset.bulletItem = ""

    const bullet = document.createElement("span")
    bullet.className = "text-sm font-semibold text-base-content/30 shrink-0 w-4 text-center"
    bullet.textContent = "-"

    const input = document.createElement("input")
    input.type = "text"
    input.className = `${this.constructor.INPUT_CLASSES} flex-1`
    input.value = ""
    input.placeholder = "Translation item…"
    input.dataset.action = "input->translation-editor#handleInput"

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "flex items-center justify-center w-6 h-6 rounded border-0 bg-transparent text-base-content/25 cursor-pointer transition-all hover:bg-error/10 hover:text-error/80 shrink-0"
    removeBtn.dataset.action = "click->translation-editor#removeItem"
    removeBtn.setAttribute("aria-label", "Remove")

    const removeIcon = document.createElement("i")
    removeIcon.className = "fa-solid fa-xmark"
    removeBtn.appendChild(removeIcon)

    row.append(bullet, input, removeBtn)
    return row
  }
}
