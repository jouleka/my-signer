const MAX_SNAPSHOTS = 50

export class HistoryManager {
  constructor() {
    this._stack = []
    this._index = -1
  }

  push(state) {
    const snapshot = JSON.parse(JSON.stringify(state))

    // Discard any redo history beyond current index
    this._stack = this._stack.slice(0, this._index + 1)
    this._stack.push(snapshot)

    // Enforce max size
    if (this._stack.length > MAX_SNAPSHOTS) {
      this._stack.shift()
    }

    this._index = this._stack.length - 1
  }

  undo() {
    if (!this.canUndo) return null
    this._index--
    return JSON.parse(JSON.stringify(this._stack[this._index]))
  }

  redo() {
    if (!this.canRedo) return null
    this._index++
    return JSON.parse(JSON.stringify(this._stack[this._index]))
  }

  get canUndo() {
    return this._index > 0
  }

  get canRedo() {
    return this._index < this._stack.length - 1
  }

  clear() {
    this._stack = []
    this._index = -1
  }
}
