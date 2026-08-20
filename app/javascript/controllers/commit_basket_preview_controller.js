import { Controller } from "@hotwired/stimulus"

// Runs inside the commit-basket modal. On every modal open it reads the
// parent keyword-editor controller's basket, renders a preview of the
// final keywords string (with new additions highlighted), shows the final
// char budget badge, and creates one hidden input per staged keyword
// (named "keywords[]") so the form submits the array.
export default class extends Controller {
  static targets = ["preview", "badge", "free", "hiddenInputs"]
  static values = { keywordsStr: String, limit: { type: Number, default: 100 } }

  connect() {
    this.dialog = this.element.closest("dialog")
    if (this.dialog) {
      this.dialog.addEventListener("close", () => this.clearHiddenInputs())
      // Native <dialog>.showModal() doesn't dispatch "open"; observe [open] attribute.
      this.dialogObserver = new MutationObserver(() => {
        if (this.dialog.open) this.render()
      })
      this.dialogObserver.observe(this.dialog, { attributes: true, attributeFilter: ["open"] })
    }
  }

  disconnect() {
    if (this.dialogObserver) this.dialogObserver.disconnect()
  }

  render() {
    const kwEditor = this.parentKeywordEditor()
    if (!kwEditor) return
    const staged = kwEditor.basket || []
    const current = (this.keywordsStrValue || "")
      .split(",").map(k => k.trim()).filter(Boolean)

    const frag = document.createDocumentFragment()
    const renderWord = (text, highlighted = false) => {
      const span = document.createElement("span")
      if (highlighted) {
        span.className = "bg-success/[0.18] text-success/90 rounded px-1"
      }
      span.textContent = text
      return span
    }

    current.forEach((kw, i) => {
      if (i > 0) frag.appendChild(document.createTextNode(", "))
      frag.appendChild(renderWord(kw))
    })
    staged.forEach((kw) => {
      if (current.length > 0 || frag.childNodes.length > 0) {
        frag.appendChild(document.createTextNode(", "))
      }
      frag.appendChild(renderWord(kw, true))
    })

    this.previewTarget.textContent = ""
    this.previewTarget.appendChild(frag)

    const final = (current.concat(staged)).join(", ")
    const count = final.length
    this.badgeTarget.textContent = `${count}/${this.limitValue}`
    this.freeTarget.textContent = `${Math.max(0, this.limitValue - count)} free after commit`

    this.populateHiddenInputs(staged)
  }

  populateHiddenInputs(staged) {
    this.clearHiddenInputs()
    staged.forEach(kw => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "keywords[]"
      input.value = kw
      this.hiddenInputsTarget.appendChild(input)
    })
  }

  clearHiddenInputs() {
    if (this.hasHiddenInputsTarget) this.hiddenInputsTarget.textContent = ""
  }

  parentKeywordEditor() {
    const el = this.element.closest("[data-controller~='keyword-editor']")
    if (!el) return null
    return this.application.getControllerForElementAndIdentifier(el, "keyword-editor")
  }
}
