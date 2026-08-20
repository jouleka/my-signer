import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static classes = ["active"]

  switch(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)

    this.tabTargets.forEach((tab, i) => {
      tab.classList.toggle("tab-active", i === index)
    })

    this.panelTargets.forEach((panel, i) => {
      panel.classList.toggle("hidden", i !== index)
    })
  }
}
