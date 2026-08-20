import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { frame: String }

  load() {
    const frame = document.getElementById(this.frameValue)
    if (frame && frame.src) {
      frame.src = frame.src
    }
  }
}
