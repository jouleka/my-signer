// Sticker drag / resize / rotate interaction state machine.
// Pure logic — no Stimulus or DOM dependencies beyond canvas dimensions.

const SNAP_ANGLES = [0, 45, 90, 135, 180, -45, -90, -135, -180]
const SNAP_THRESHOLD = 3

export class StickerInteraction {
  constructor() {
    this.reset()
  }

  reset() {
    this._mode = null          // "drag" | "resize" | "rotate" | null
    this._sticker = null       // active sticker reference
    this._dragStartPos = null
    this._resizeHandleIndex = -1
    this._resizeStartY = 0
    this._resizeStartSize = 64
    this._rotateStartAngle = 0
    this._rotateStartRotation = 0
  }

  get active() { return this._mode !== null }
  get mode() { return this._mode }

  // --- Drag ---

  startDrag(sticker, pos) {
    this._mode = "drag"
    this._sticker = sticker
    this._dragStartPos = pos
  }

  duringDrag(pos, canvasWidth, canvasHeight) {
    if (this._mode !== "drag" || !this._sticker) return false
    const xPct = (pos.x / canvasWidth) * 100
    const yPct = (pos.y / canvasHeight) * 100
    this._sticker.x = Math.max(2, Math.min(98, Math.round(xPct * 10) / 10))
    this._sticker.y = Math.max(2, Math.min(98, Math.round(yPct * 10) / 10))
    return true
  }

  // --- Resize ---

  startResize(sticker, pos, handleIdx) {
    this._mode = "resize"
    this._sticker = sticker
    this._resizeHandleIndex = handleIdx
    this._resizeStartY = pos.y
    this._resizeStartSize = sticker ? sticker.size : 64
  }

  duringResize(pos, canvasWidth) {
    if (this._mode !== "resize" || !this._sticker) return false
    const deltaY = pos.y - this._resizeStartY
    // Bottom handles (2,3): drag down = bigger. Top handles (0,1): drag up = bigger.
    const sign = (this._resizeHandleIndex >= 2) ? 1 : -1
    const scale = canvasWidth / 1080
    const sizeDelta = (deltaY * sign) / scale * 0.5
    this._sticker.size = Math.round(Math.max(24, Math.min(400, this._resizeStartSize + sizeDelta)))
    return true
  }

  // --- Rotate ---

  startRotate(sticker, pos, canvasWidth, canvasHeight) {
    this._mode = "rotate"
    this._sticker = sticker
    if (!sticker) return
    const cx = canvasWidth * (sticker.x / 100)
    const cy = canvasHeight * (sticker.y / 100)
    this._rotateStartAngle = Math.atan2(pos.y - cy, pos.x - cx)
    this._rotateStartRotation = sticker.rotation || 0
  }

  duringRotate(pos, canvasWidth, canvasHeight) {
    if (this._mode !== "rotate" || !this._sticker) return false
    const cx = canvasWidth * (this._sticker.x / 100)
    const cy = canvasHeight * (this._sticker.y / 100)
    const currentAngle = Math.atan2(pos.y - cy, pos.x - cx)
    const deltaAngle = (currentAngle - this._rotateStartAngle) * 180 / Math.PI
    let newRotation = this._rotateStartRotation + deltaAngle

    // Normalize to -180..180
    while (newRotation > 180) newRotation -= 360
    while (newRotation < -180) newRotation += 360

    // Snap to common angles
    for (const snap of SNAP_ANGLES) {
      if (Math.abs(newRotation - snap) < SNAP_THRESHOLD) {
        newRotation = snap
        break
      }
    }

    this._sticker.rotation = Math.round(newRotation * 10) / 10
    return true
  }

  // --- End (common) ---

  end() {
    const wasActive = this._mode
    this.reset()
    return wasActive
  }
}
