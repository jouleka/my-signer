import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "label"]
  static values = { autoSubmit: Boolean }

  connect() {
    this.closeHandler = (e) => {
      if (!this.element.contains(e.target)) {
        this.element.removeAttribute("open")
      }
    }
    document.addEventListener("click", this.closeHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.closeHandler)
  }

  select(event) {
    event.preventDefault()
    event.stopPropagation()
    const value = event.currentTarget.dataset.value
    const label = event.currentTarget.dataset.label || value
    this.inputTarget.value = value
    this.labelTarget.textContent = label

    // Copy font-family style to the label if present
    if (event.currentTarget.style.fontFamily) {
      this.labelTarget.style.fontFamily = event.currentTarget.style.fontFamily
    }

    // Update active class on menu items
    this.element.querySelectorAll("ul a").forEach(a => {
      a.classList.toggle("active", a.dataset.value === value)
    })

    // Clear search input if present
    const searchInput = this.element.querySelector(".font-search-input")
    if (searchInput) {
      searchInput.value = ""
      this.filterFonts({ currentTarget: searchInput })
    }

    this.element.removeAttribute("open")
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))

    if (this.autoSubmitValue) {
      this.inputTarget.closest("form")?.requestSubmit()
    }
  }

  filterFonts(event) {
    const query = event.currentTarget.value.toLowerCase().trim()
    const options = this.element.querySelectorAll(".font-option")
    const headers = this.element.querySelectorAll(".font-category-header")
    const noResults = this.element.querySelector(".font-no-results")
    let anyVisible = false

    options.forEach(li => {
      const label = li.querySelector("a")?.dataset.value?.toLowerCase() || ""
      const match = !query || label.includes(query)
      li.classList.toggle("hidden", !match)
      if (match) anyVisible = true
    })

    // Hide category headers if all their fonts are hidden
    headers.forEach(header => {
      let next = header.nextElementSibling
      let hasVisible = false
      while (next && !next.classList.contains("font-category-header")) {
        if (next.classList.contains("font-option") && !next.classList.contains("hidden")) {
          hasVisible = true
          break
        }
        next = next.nextElementSibling
      }
      header.classList.toggle("hidden", !hasVisible)
    })

    if (noResults) {
      noResults.classList.toggle("hidden", anyVisible)
    }
  }
}
