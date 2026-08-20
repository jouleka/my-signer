import { Controller } from "@hotwired/stimulus";

// Swaps visible rows in the compare table based on the selected category tab.
// Uses [data-category] on each row + [data-compare-category] on each tab button.
// Reads/writes URL fragment `#compare=<category>` for deep linking.
export default class extends Controller {
  static targets = ["tab", "row"];

  connect() {
    const hash = (window.location.hash || "").match(/compare=([a-z-]+)/i);
    const initial = hash ? hash[1] : this._firstCategory();
    this._setActive(initial);
  }

  select(event) {
    const category = event.currentTarget.dataset.compareCategory;
    this._setActive(category);
    history.replaceState(null, "", `#compare=${category}`);
  }

  _firstCategory() {
    return this.tabTargets[0]?.dataset.compareCategory || "overview";
  }

  _setActive(category) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.compareCategory === category;
      tab.setAttribute("data-active", String(active));
      tab.setAttribute("aria-selected", String(active));
    });
    this.rowTargets.forEach((row) => {
      const match = row.dataset.category === category;
      row.hidden = !match;
    });
  }
}
