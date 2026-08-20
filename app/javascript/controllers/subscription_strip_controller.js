import { Controller } from "@hotwired/stimulus";

// Collapsible "your subscription" strip at the top of /pricing.
// Collapsed shows plan + renewal + next-charge + Manage button.
// Expanded also shows payment method + invoices + cancel link.
export default class extends Controller {
  static targets = ["panel", "toggle"];

  connect() {
    this._setExpanded(false);
  }

  toggle() {
    this._setExpanded(this.panelTarget.hidden);
  }

  _setExpanded(expanded) {
    this.panelTarget.hidden = !expanded;
    this.toggleTarget.setAttribute("aria-expanded", String(expanded));
    const icon = this.toggleTarget.querySelector("[data-chevron]");
    if (icon) icon.style.transform = expanded ? "rotate(180deg)" : "";
  }
}
