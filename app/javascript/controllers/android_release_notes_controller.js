import { Controller } from "@hotwired/stimulus"

// Manages the per-locale release-notes rows on the Android CLI Defaults form.
// Adds / removes rows client-side; the submit-time serializer in edit.html.erb
// converts the parallel arrays into params[:android_release][:release_notes].
export default class extends Controller {
  add(event) {
    event.preventDefault()
    const list = this.element.querySelector("#release-notes-rows")
    if (!list) return

    const row = this._buildRow()
    list.appendChild(row)
    row.querySelector("input")?.focus()
  }

  remove(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-release-note-row]")
    const list = this.element.querySelector("#release-notes-rows")
    if (!row) return

    // Keep at least one row so users can always re-add text without re-clicking "Add".
    if (list && list.children.length === 1) {
      const keyInput = row.querySelector("input[type='text']")
      const textArea = row.querySelector("textarea")
      if (keyInput) keyInput.value = ""
      if (textArea) textArea.value = ""
      return
    }
    row.remove()
  }

  _buildRow() {
    const row = document.createElement("div")
    row.className = "group flex gap-2 items-start"
    row.dataset.releaseNoteRow = ""

    const locale = document.createElement("input")
    locale.type = "text"
    locale.name = "android_release[release_notes_keys][]"
    locale.placeholder = "en-US"
    locale.setAttribute("aria-label", "Locale")
    locale.className = "input input-bordered input-sm font-mono w-24 sm:w-28 shrink-0 focus:input-primary"

    const wrap = document.createElement("div")
    wrap.className = "flex-1 min-w-0"

    const textarea = document.createElement("textarea")
    textarea.name = "android_release[release_notes_values][]"
    textarea.rows = 1
    textarea.placeholder = "What's new in this release?"
    textarea.setAttribute("aria-label", "Release note text")
    textarea.className = "textarea textarea-bordered textarea-sm w-full text-sm focus:textarea-primary leading-relaxed resize-y min-h-10"
    wrap.appendChild(textarea)

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.dataset.action = "click->android-release-notes#remove"
    removeBtn.className = "btn btn-ghost btn-sm btn-square text-base-content/40 hover:text-error hover:bg-error/10 shrink-0"
    removeBtn.setAttribute("aria-label", "Remove locale")

    const icon = document.createElement("i")
    icon.className = "fa-solid fa-xmark text-xs"
    removeBtn.appendChild(icon)

    row.append(locale, wrap, removeBtn)
    return row
  }
}
