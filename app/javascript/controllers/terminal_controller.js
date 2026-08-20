import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    lines: Array,
    typingSpeed: Number,
    linePause: Number,
    loop: Boolean
  }

  initialize() {
    this._timeouts = []
    this._isDisconnected = false
    this._hasStarted = false
  }

  connect() {
    this._isDisconnected = false

    // Defaults
    if (!this.hasTypingSpeedValue) this.typingSpeedValue = 28
    if (!this.hasLinePauseValue) this.linePauseValue = 700
    if (!this.hasLoopValue) this.loopValue = true

    // Accessibility: respect reduced motion
    const prefersReduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (prefersReduced) {
      this.typingSpeedValue = 0
    }

    // Start animation with retry mechanism for cold cache
    this._tryStart(0)
  }

  _tryStart(attempt) {
    if (this._isDisconnected || this._hasStarted) return

    const lines = this._getLines()
    if (lines && lines.length > 0) {
      this._lines = lines
      this._hasStarted = true
      this._animate()
    } else if (attempt < 20) {
      const delay = 50 + (attempt * 50)
      const id = setTimeout(() => this._tryStart(attempt + 1), delay)
      this._timeouts.push(id)
    }
  }

  _getLines() {
    if (this.linesValue && this.linesValue.length > 0) {
      return this.linesValue
    }

    const raw = this.element?.dataset?.terminalLinesValue
    if (raw) {
      try {
        const parsed = JSON.parse(raw)
        if (Array.isArray(parsed) && parsed.length > 0) {
          return parsed
        }
      } catch (e) {
        // Ignore parse errors, will retry
      }
    }

    return null
  }

  disconnect() {
    this._isDisconnected = true
    this._clearTimers()
  }

  async _animate() {
    while (!this._isDisconnected) {
      await this._typeAllLines()
      if (!this.loopValue) break
      await this._sleep(1200)
      this._clearOutput()
    }
  }

  async _typeAllLines() {
    this._clearOutput()
    for (const line of this._lines) {
      if (this._isDisconnected) return

      const pre = document.createElement("pre")
      pre.className = "whitespace-pre-wrap"
      if (line.prefix) {
        pre.dataset.prefix = line.prefix
      }
      if (line.class) {
        pre.classList.add(...line.class.split(" "))
      }

      this.element.appendChild(pre)
      this._scrollToBottom()

      if (line.text) {
        await this._typeLine(line.text, pre)
      }

      await this._sleep(this.linePauseValue)
    }
  }

  _clearOutput() {
    this.element.innerHTML = ""
    this.element.scrollTop = 0
  }

  _sleep(ms) {
    return new Promise((resolve) => {
      const id = setTimeout(resolve, ms)
      this._timeouts.push(id)
    })
  }

  _clearTimers() {
    this._timeouts.forEach((id) => clearTimeout(id))
    this._timeouts = []
  }

  _typeLine(text, element) {
    return new Promise((resolve) => {
      if (this.typingSpeedValue <= 0) {
        element.textContent = text
        resolve()
        return
      }

      let index = 0
      const step = () => {
        if (this._isDisconnected) return
        if (index >= text.length) {
          resolve()
          return
        }
        element.textContent += text.charAt(index)
        this._scrollToBottom()
        index += 1
        const id = setTimeout(step, this.typingSpeedValue)
        this._timeouts.push(id)
      }
      step()
    })
  }

  _scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
