import { Controller } from "@hotwired/stimulus"

// Submits the containing form when the element fires a change event. Replaces
// inline `onchange="this.form.submit()"` which is blocked by the production
// CSP (script-src without 'unsafe-inline' or 'unsafe-hashes').
//
// Usage:
//   <select data-controller="submit-on-change" data-action="change->submit-on-change#submit">
//     ...
//   </select>
export default class extends Controller {
  submit(event) {
    const form = event.target.form || this.element.closest("form")
    form?.requestSubmit()
  }
}
