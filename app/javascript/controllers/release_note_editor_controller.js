import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "newList", "improvedList", "fixedList",
    "preview", "charCount", "charBar",
    "templatePanel", "freeformPanel",
    "renderedTextInput", "freeformInput",
    "templateDataInput"
  ]

  static values = {
    charLimit: Number,
    platform: String
  }

  connect() {
    this.updatePreview()
  }

  // ── Add / Remove items ──

  addItem(event) {
    event.preventDefault()
    const category = event.params.category
    const list = this._listTarget(category)
    if (!list) return

    const row = this._buildItemRow(category, "")
    list.appendChild(row)
    row.querySelector("input").focus()
    this.updatePreview()
  }

  removeItem(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-bullet-item]")
    if (row) {
      row.remove()
      this.updatePreview()
    }
  }

  // ── Preview rendering (debounced) ──

  updatePreview() {
    clearTimeout(this._previewTimeout)
    this._previewTimeout = setTimeout(() => this._renderPreview(), 150)
  }

  // ── Mode switching ──

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

    // Copy current rendered text to freeform textarea
    if (this.hasFreeformInputTarget && this.hasRenderedTextInputTarget) {
      this.freeformInputTarget.value = this.renderedTextInputTarget.value
    }

    this._setActiveTab("freeform")
  }

  syncFromFreeform() {
    if (!this.hasFreeformInputTarget || !this.hasRenderedTextInputTarget) return

    this.renderedTextInputTarget.value = this.freeformInputTarget.value
    this._updatePreviewContent(this.freeformInputTarget.value)
    this._updateCharCount(this.freeformInputTarget.value)
  }

  // ── Private ──

  _renderPreview() {
    const templateData = { new: [], improved: [], fixed: [] }
    const headings = { new: "NEW", improved: "IMPROVED", fixed: "FIXED" }
    const lines = []

    ;["new", "improved", "fixed"].forEach(category => {
      const list = this._listTarget(category)
      if (!list) return

      const inputs = list.querySelectorAll("input[type='text']")
      const items = []
      inputs.forEach(input => {
        const val = input.value.trim()
        if (val) items.push(val)
      })

      templateData[category] = items

      if (items.length > 0) {
        lines.push(headings[category])
        items.forEach(item => lines.push(`- ${item}`))
        lines.push("")
      }
    })

    const rendered = lines.join("\n").trim()

    // Update hidden inputs
    if (this.hasRenderedTextInputTarget) {
      this.renderedTextInputTarget.value = rendered
    }
    if (this.hasTemplateDataInputTarget) {
      this.templateDataInputTarget.value = JSON.stringify(templateData)
    }

    this._updatePreviewContent(rendered)
    this._updateCharCount(rendered)
  }

  _updatePreviewContent(text) {
    if (!this.hasPreviewTarget) return

    if (text) {
      this.previewTarget.textContent = text
      this.previewTarget.classList.remove("opacity-30", "italic")
    } else {
      this.previewTarget.textContent = "Release notes will appear here..."
      this.previewTarget.classList.add("opacity-30", "italic")
    }
  }

  _updateCharCount(text) {
    const length = text.length
    const limit = this.charLimitValue

    if (this.hasCharCountTarget) {
      this.charCountTarget.textContent = `${length}/${limit}`

      // Remove all variant classes first
      this.charCountTarget.classList.remove(
        "bg-warning/10", "text-warning/80",
        "bg-error/[0.12]", "text-error/90", "font-bold",
        "bg-base-content/[0.04]", "text-base-content/30"
      )
      if (limit > 0 && length > limit) {
        this.charCountTarget.classList.add("bg-error/[0.12]", "text-error/90", "font-bold")
      } else if (limit > 0 && length > limit * 0.9) {
        this.charCountTarget.classList.add("bg-warning/10", "text-warning/80")
      } else {
        this.charCountTarget.classList.add("bg-base-content/[0.04]", "text-base-content/30")
      }
    }

    if (this.hasCharBarTarget && limit > 0) {
      const pct = Math.min((length / limit) * 100, 100)
      this.charBarTarget.style.width = `${pct}%`

      this.charBarTarget.classList.remove("bg-warning/60", "bg-error/70", "bg-primary/35")
      if (length > limit) {
        this.charBarTarget.classList.add("bg-error/70")
      } else if (length > limit * 0.9) {
        this.charBarTarget.classList.add("bg-warning/60")
      } else {
        this.charBarTarget.classList.add("bg-primary/35")
      }
    }
  }

  _listTarget(category) {
    switch (category) {
      case "new": return this.hasNewListTarget ? this.newListTarget : null
      case "improved": return this.hasImprovedListTarget ? this.improvedListTarget : null
      case "fixed": return this.hasFixedListTarget ? this.fixedListTarget : null
      default: return null
    }
  }

  // MUST MATCH UiHelper::INPUT (app/helpers/ui_helper.rb). Any drift will cause dynamically-added
  // bullet inputs to visually diverge from the rest of the release-tab forms.
  static INPUT_CLASSES = "block w-full text-sm leading-relaxed px-3 py-2 rounded-lg border border-base-content/[0.1] bg-base-content/[0.03] text-base-content/85 outline-none transition-[border-color,box-shadow,background] duration-150 hover:border-base-content/15 focus:border-primary/40 focus:bg-base-content/[0.05] focus:shadow-[0_0_0_3px_oklch(var(--color-primary)/0.08)]"

  _buildItemRow(category, value) {
    const row = document.createElement("div")
    row.className = "flex gap-2 items-center mb-2"
    row.dataset.bulletItem = ""

    const bullet = document.createElement("span")
    bullet.className = "text-sm font-semibold text-base-content/30 shrink-0 w-4 text-center"
    bullet.textContent = "-"

    const input = document.createElement("input")
    input.type = "text"
    input.className = `${this.constructor.INPUT_CLASSES} flex-1`
    input.value = value
    input.placeholder = `Add ${category} item...`
    input.dataset.action = "input->release-note-editor#updatePreview"

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "flex items-center justify-center w-6 h-6 rounded border-0 bg-transparent text-base-content/25 cursor-pointer transition-all hover:bg-error/10 hover:text-error/80 shrink-0"
    removeBtn.dataset.action = "click->release-note-editor#removeItem"

    const removeIcon = document.createElement("i")
    removeIcon.className = "fa-solid fa-xmark"
    removeBtn.appendChild(removeIcon)

    row.append(bullet, input, removeBtn)
    return row
  }

  _setActiveTab(active) {
    // Only flip tabs that trigger this controller — prevents this method from
    // toggling tabs inside a translation-editor which lives under the same
    // parent section.
    const tabs = this.element.querySelectorAll("[data-mode-tab]")
    tabs.forEach(tab => {
      const action = tab.dataset.action || ""
      if (!action.includes("release-note-editor#")) return
      const mode = tab.dataset.modeTab
      tab.classList.toggle("is-tab-active", mode === active)
      tab.classList.toggle("is-tab-inactive", mode !== active)
    })
  }
}
