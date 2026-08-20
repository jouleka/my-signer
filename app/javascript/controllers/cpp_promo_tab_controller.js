import { Controller } from "@hotwired/stimulus"

// Switches between promotional text locale panels in CPP overview.
// Replaces inline onclick handlers to avoid interpolating Ruby into JS context.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static classes = ["active", "inactive"]

  switch(event) {
    const locale = event.currentTarget.dataset.locale

    this.tabTargets.forEach(t => {
      t.className = (t.dataset.locale === locale ? this.activeClass : this.inactiveClass) + " cpp-promo-tab"
    })

    this.panelTargets.forEach(p => {
      p.classList.toggle("hidden", p.dataset.locale !== locale)
    })
  }
}
