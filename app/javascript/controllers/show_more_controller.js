import { Controller } from "@hotwired/stimulus"

// Simple show-more/show-less controller for lists
// Usage:
//   <div data-controller="show-more" data-show-more-limit-value="10">
//     <div data-show-more-target="item">Item 1</div>
//     <div data-show-more-target="item">Item 2</div>
//     ...
//     <button data-show-more-target="button" data-action="click->show-more#toggle">
//       Show more
//     </button>
//   </div>

export default class extends Controller {
  static targets = ["item", "button", "count"]
  static values = { 
    limit: { type: Number, default: 10 },
    expanded: { type: Boolean, default: false }
  }

  connect() {
    this.updateVisibility()
  }

  toggle() {
    this.expandedValue = !this.expandedValue
    this.updateVisibility()
  }

  updateVisibility() {
    const items = this.itemTargets
    const limit = this.limitValue
    const hiddenCount = items.length - limit

    items.forEach((item, index) => {
      if (this.expandedValue || index < limit) {
        item.classList.remove("hidden")
      } else {
        item.classList.add("hidden")
      }
    })

    // Update button text and visibility
    if (this.hasButtonTarget) {
      if (hiddenCount <= 0) {
        this.buttonTarget.classList.add("hidden")
      } else {
        this.buttonTarget.classList.remove("hidden")
        if (this.expandedValue) {
          this.buttonTarget.innerHTML = `<i class="fa-solid fa-chevron-up mr-1"></i> Show less`
        } else {
          this.buttonTarget.innerHTML = `<i class="fa-solid fa-chevron-down mr-1"></i> Show ${hiddenCount} more`
        }
      }
    }

    // Update count badge if present
    if (this.hasCountTarget) {
      this.countTarget.textContent = this.expandedValue ? 
        `${items.length} shown` : 
        `${Math.min(limit, items.length)} of ${items.length}`
    }
  }
}

