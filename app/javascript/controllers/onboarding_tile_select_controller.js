import { Controller } from "@hotwired/stimulus"

// Drives the "selected" visual state on the onboarding tile/perm rows.
// Replaces inline onchange handlers that were being blocked by CSP.
//
// Markup contract: the controller is on the row element (.tiles or
// .perm-row). Each interactive cell has a single radio/checkbox input
// nested inside a `.tile` or `.perm` wrapper. Changing any input
// re-evaluates ALL wrappers and toggles `.is-selected` on whichever
// one currently contains a checked input. This matches the previous
// inline handler exactly:
//   this.closest('.tiles').querySelectorAll('.tile')
//     .forEach(el => el.classList.toggle('is-selected', el.contains(this)))
//
// Configurable via the `wrapperClass` value so the same controller
// drives both tile rows (organization step) and perm rows (token step).
export default class extends Controller {
  static values = {
    wrapperClass: { type: String, default: "tile" }
  }

  refresh(event) {
    const wrappers = this.element.querySelectorAll(`.${this.wrapperClassValue}`)
    const changed = event?.target
    wrappers.forEach((wrapper) => {
      const input = wrapper.querySelector('input[type="radio"], input[type="checkbox"]')
      const isSelected = input ? input.checked : (changed ? wrapper.contains(changed) : false)
      wrapper.classList.toggle("is-selected", isSelected)
    })
  }
}
