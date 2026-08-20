import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["device", "toggleBtn"]

  toggleDevice() {
    const device = this.deviceTarget
    const isIOS = device.dataset.device !== "android"

    if (isIOS) {
      device.dataset.device = "android"
      device.style.borderRadius = "1.5rem"
      const icon = this.toggleBtnTarget.querySelector("i")
      if (icon) icon.className = "fa-brands fa-google-play"
      const text = this.toggleBtnTarget.childNodes[this.toggleBtnTarget.childNodes.length - 1]
      if (text && text.nodeType === Node.TEXT_NODE) text.textContent = " Pixel"
    } else {
      device.dataset.device = "ios"
      device.style.borderRadius = "2.5rem"
      const icon = this.toggleBtnTarget.querySelector("i")
      if (icon) icon.className = "fa-brands fa-apple"
      const text = this.toggleBtnTarget.childNodes[this.toggleBtnTarget.childNodes.length - 1]
      if (text && text.nodeType === Node.TEXT_NODE) text.textContent = " iPhone"
    }
  }
}
