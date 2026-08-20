import { Controller } from "@hotwired/stimulus"

// Docs search controller
// Provides real-time search across documentation pages
export default class extends Controller {
  static targets = ["input", "results", "overlay"]
  static values = {
    pages: { type: Array, default: [] }
  }

  connect() {
    this.isOpen = false
    this.selectedIndex = -1
    
    // Listen for keyboard shortcut (Cmd/Ctrl + K)
    this.handleGlobalKeydown = this.handleGlobalKeydown.bind(this)
    document.addEventListener("keydown", this.handleGlobalKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleGlobalKeydown)
  }

  handleGlobalKeydown(event) {
    // Open search with Cmd/Ctrl + K
    if ((event.metaKey || event.ctrlKey) && event.key === "k") {
      event.preventDefault()
      this.open()
    }
    
    // Close with Escape
    if (event.key === "Escape" && this.isOpen) {
      this.close()
    }
  }

  open() {
    this.isOpen = true
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("hidden")
      this.overlayTarget.classList.add("flex")
    }
    this.inputTarget.focus()
    this.inputTarget.select()
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.isOpen = false
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
      this.overlayTarget.classList.remove("flex")
    }
    this.inputTarget.value = ""
    this.clearResults()
    document.body.classList.remove("overflow-hidden")
  }

  search() {
    const query = this.inputTarget.value.toLowerCase().trim()
    
    if (query.length < 2) {
      this.clearResults()
      return
    }

    const results = this.pagesValue.filter((page) => {
      const titleMatch = page.title.toLowerCase().includes(query)
      const descMatch = page.description?.toLowerCase().includes(query)
      const categoryMatch = page.category.toLowerCase().includes(query)
      return titleMatch || descMatch || categoryMatch
    })

    this.renderResults(results, query)
  }

  renderResults(results, query) {
    this.selectedIndex = -1
    
    if (results.length === 0) {
      this.resultsTarget.innerHTML = `
        <div class="p-6 text-center text-base-content/60">
          <i class="fa-solid fa-search text-2xl mb-2 opacity-50"></i>
          <p>No results found for "<span class="font-medium">${this.escapeHtml(query)}</span>"</p>
        </div>
      `
      return
    }

    const html = results.slice(0, 8).map((page, index) => `
      <a href="${page.path}" 
         class="search-result flex items-center gap-3 px-4 py-3 hover:bg-base-200 transition-colors"
         data-index="${index}"
         data-action="mouseenter->docs-search#highlightResult keydown.enter->docs-search#navigateToResult">
        <i class="${page.icon} w-5 text-center text-base-content/50"></i>
        <div class="flex-1 min-w-0">
          <div class="font-medium truncate">${this.highlightMatch(page.title, query)}</div>
          <div class="text-xs text-base-content/50">${page.categoryTitle}</div>
        </div>
        <i class="fa-solid fa-chevron-right text-xs text-base-content/30"></i>
      </a>
    `).join("")

    this.resultsTarget.innerHTML = html
  }

  clearResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.innerHTML = `
        <div class="p-6 text-center text-base-content/50">
          <p class="text-sm">Start typing to search documentation...</p>
          <p class="text-xs mt-2 opacity-60">Press <kbd class="kbd kbd-xs">↵</kbd> to select, <kbd class="kbd kbd-xs">esc</kbd> to close</p>
        </div>
      `
    }
  }

  navigate(event) {
    const results = this.resultsTarget.querySelectorAll(".search-result")
    if (results.length === 0) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectedIndex = Math.min(this.selectedIndex + 1, results.length - 1)
      this.updateSelection(results)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
      this.updateSelection(results)
    } else if (event.key === "Enter" && this.selectedIndex >= 0) {
      event.preventDefault()
      results[this.selectedIndex].click()
    }
  }

  updateSelection(results) {
    results.forEach((result, index) => {
      if (index === this.selectedIndex) {
        result.classList.add("bg-primary/10", "border-l-2", "border-primary")
        result.scrollIntoView({ block: "nearest" })
      } else {
        result.classList.remove("bg-primary/10", "border-l-2", "border-primary")
      }
    })
  }

  highlightResult(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    if (!isNaN(index)) {
      this.selectedIndex = index
      const results = this.resultsTarget.querySelectorAll(".search-result")
      this.updateSelection(results)
    }
  }

  selectResult() {
    // Close the search modal when a result is clicked
    this.close()
  }

  highlightMatch(text, query) {
    const regex = new RegExp(`(${this.escapeRegex(query)})`, "gi")
    return text.replace(regex, '<mark class="bg-primary/20 px-0.5 rounded">$1</mark>')
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  escapeRegex(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }

  clickOverlay(event) {
    if (event.target === this.overlayTarget) {
      this.close()
    }
  }
}
