import { Controller } from "@hotwired/stimulus"

// Pairs an <input type="color"> with an adjacent hex text input so editing
// either updates the other. Use:
//
//   <div data-controller="color-sync" class="flex items-center gap-2">
//     <input type="color" data-action="input->color-sync#sync">
//     <input type="text"  data-action="input->color-sync#sync">
//   </div>
//
// The pair is inferred from DOM adjacency (previousElementSibling /
// nextElementSibling) to keep the markup minimal. Replaces inline
// `oninput="..."` handlers that were blocked by the production CSP.
export default class extends Controller {
  sync(event) {
    const el = event.target
    if (el.type === "color") {
      const text = el.nextElementSibling
      if (text && text.tagName === "INPUT") text.value = el.value
    } else {
      if (!/^#[0-9a-fA-F]{6}$/.test(el.value)) return
      const color = el.previousElementSibling
      if (color && color.type === "color") color.value = el.value
    }
  }
}
