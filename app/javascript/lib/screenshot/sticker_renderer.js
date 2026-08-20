// Sticker rendering and hit-testing for screenshot editor
// Renders emoji and SVG asset stickers on canvas

import { getStickerImage } from "lib/screenshot/sticker_image_cache"
import { getCustomImage } from "lib/screenshot/custom_image_cache"

/**
 * Render all stickers onto the canvas.
 * Returns an array of sticker bounds for hit-testing.
 *
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} canvasWidth
 * @param {number} canvasHeight
 * @param {Array} stickers - array of sticker objects (emoji or asset type)
 * @param {string|null} selectedId - currently selected sticker ID
 * @param {boolean} showHandles - whether to draw selection UI
 * @returns {Array} bounds - array of { id, x, y, width, height, rotation, centerX, centerY }
 */
export function renderStickers(ctx, canvasWidth, canvasHeight, stickers, selectedId, showHandles) {
  if (!stickers || stickers.length === 0) return []

  const scale = canvasWidth / 1080
  const bounds = []

  for (const sticker of stickers) {
    const pixelSize = sticker.size * scale
    const cx = canvasWidth * (sticker.x / 100)
    const cy = canvasHeight * (sticker.y / 100)
    const rotation = sticker.rotation || 0
    const rotationRad = rotation * Math.PI / 180
    const stickerType = sticker.type || "emoji"

    ctx.save()

    // Apply rotation around sticker center
    if (rotation !== 0) {
      ctx.translate(cx, cy)
      ctx.rotate(rotationRad)
      ctx.translate(-cx, -cy)
    }

    let w, h

    if (stickerType === "asset") {
      // SVG image sticker — use ctx.drawImage() with cached Image
      const img = getStickerImage(sticker.asset_key, sticker.color)
      if (img) {
        const aspect = img.naturalWidth / img.naturalHeight
        w = aspect >= 1 ? pixelSize : pixelSize * aspect
        h = aspect >= 1 ? pixelSize / aspect : pixelSize
        ctx.drawImage(img, cx - w / 2, cy - h / 2, w, h)

        // Post-render text overlay for speech/thought/callout bubble asset stickers
        if (sticker.text && (sticker.asset_key === "anno_speech_bubble" || sticker.asset_key === "anno_thought_bubble" || sticker.asset_key === "anno_callout_box")) {
          const fontSize = Math.max(10, pixelSize * 0.18)
          ctx.font = `700 ${fontSize}px "Inter", "Arial", sans-serif`
          ctx.fillStyle = sticker.color || "#FFFFFF"
          ctx.textAlign = "center"
          ctx.textBaseline = "middle"
          ctx.fillText(sticker.text, cx, cy - pixelSize * 0.06, w * 0.75)
        }
      } else {
        // Placeholder while loading
        w = h = pixelSize
        ctx.fillStyle = "rgba(200,200,200,0.3)"
        ctx.fillRect(cx - w / 2, cy - h / 2, w, h)
      }
    } else if (stickerType === "custom_image") {
      // Custom uploaded image sticker — use ctx.drawImage() with cached Image
      const img = getCustomImage(sticker.image_url)
      if (img) {
        const aspect = img.naturalWidth / img.naturalHeight
        w = aspect >= 1 ? pixelSize : pixelSize * aspect
        h = aspect >= 1 ? pixelSize / aspect : pixelSize
        ctx.drawImage(img, cx - w / 2, cy - h / 2, w, h)
      } else {
        // Gray placeholder while loading
        w = h = pixelSize
        ctx.fillStyle = "rgba(200,200,200,0.3)"
        ctx.fillRect(cx - w / 2, cy - h / 2, w, h)
      }
    } else if (stickerType === "text") {
      // Text label sticker — renders arbitrary text with optional background pill
      const fontSize = Math.max(8, pixelSize * 0.45)
      const fontWeight = sticker.fontWeight || "700"
      const fontFamily = sticker.fontFamily || '"Inter", "Arial", sans-serif'
      ctx.font = `${fontWeight} ${fontSize}px ${fontFamily}`
      ctx.textAlign = "center"
      ctx.textBaseline = "middle"

      const displayText = sticker.text || "Text"
      const metrics = ctx.measureText(displayText)
      const textW = metrics.width
      const textH = fontSize * 1.3
      w = textW + fontSize * 0.8
      h = textH + fontSize * 0.4

      // Background pill
      if (sticker.bgEnabled !== false) {
        const bgColor = sticker.bgColor || "rgba(0,0,0,0.7)"
        const radius = Math.min(h / 2, fontSize * 0.4)
        ctx.fillStyle = bgColor
        ctx.beginPath()
        if (ctx.roundRect) {
          ctx.roundRect(cx - w / 2, cy - h / 2, w, h, radius)
        } else {
          // Manual arc-based roundRect fallback for Safari < 15.4
          const x = cx - w / 2, y = cy - h / 2
          ctx.moveTo(x + radius, y)
          ctx.lineTo(x + w - radius, y)
          ctx.arcTo(x + w, y, x + w, y + radius, radius)
          ctx.lineTo(x + w, y + h - radius)
          ctx.arcTo(x + w, y + h, x + w - radius, y + h, radius)
          ctx.lineTo(x + radius, y + h)
          ctx.arcTo(x, y + h, x, y + h - radius, radius)
          ctx.lineTo(x, y + radius)
          ctx.arcTo(x, y, x + radius, y, radius)
        }
        ctx.fill()
      }

      // Text
      ctx.fillStyle = sticker.color || "#FFFFFF"
      ctx.fillText(displayText, cx, cy)
    } else {
      // Emoji (existing fillText code)
      ctx.font = `${pixelSize}px "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif`
      ctx.textAlign = "center"
      ctx.textBaseline = "middle"
      ctx.fillText(sticker.emoji, cx, cy)
      const metrics = ctx.measureText(sticker.emoji)
      w = metrics.width
      h = pixelSize
    }

    const bx = cx - w / 2
    const by = cy - h / 2

    // Draw selection handles for selected sticker
    if (showHandles && sticker.id === selectedId) {
      const pad = 6
      const sx = bx - pad
      const sy = by - pad
      const sw = w + pad * 2
      const sh = h + pad * 2

      // Dashed selection border
      ctx.strokeStyle = "rgba(99, 102, 241, 0.6)"
      ctx.lineWidth = 1.5
      ctx.setLineDash([4, 4])
      ctx.strokeRect(sx, sy, sw, sh)
      ctx.setLineDash([])

      // Corner dots
      ctx.fillStyle = "rgba(99, 102, 241, 0.9)"
      const dotR = 3.5
      const corners = [
        [sx, sy], [sx + sw, sy],
        [sx, sy + sh], [sx + sw, sy + sh]
      ]
      for (const [dx, dy] of corners) {
        ctx.beginPath()
        ctx.arc(dx, dy, dotR, 0, Math.PI * 2)
        ctx.fill()
      }

      // Delete button (top-right, offset)
      const delX = sx + sw + 6
      const delY = sy - 6
      const delR = 8
      ctx.fillStyle = "rgba(239, 68, 68, 0.9)"
      ctx.beginPath()
      ctx.arc(delX, delY, delR, 0, Math.PI * 2)
      ctx.fill()
      ctx.strokeStyle = "#FFFFFF"
      ctx.lineWidth = 1.5
      const cross = 3.5
      ctx.beginPath()
      ctx.moveTo(delX - cross, delY - cross)
      ctx.lineTo(delX + cross, delY + cross)
      ctx.moveTo(delX + cross, delY - cross)
      ctx.lineTo(delX - cross, delY + cross)
      ctx.stroke()

      // Rotation handle: stem from top-center upward + circle
      const stemLength = 20
      const topCenterX = sx + sw / 2
      const topCenterY = sy
      const handleX = topCenterX
      const handleY = topCenterY - stemLength

      ctx.strokeStyle = "rgba(99, 102, 241, 0.7)"
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.moveTo(topCenterX, topCenterY)
      ctx.lineTo(handleX, handleY)
      ctx.stroke()

      ctx.fillStyle = "rgba(99, 102, 241, 0.9)"
      ctx.beginPath()
      ctx.arc(handleX, handleY, 5, 0, Math.PI * 2)
      ctx.fill()

      // Arc arrow icon
      ctx.strokeStyle = "#FFFFFF"
      ctx.lineWidth = 1.2
      ctx.beginPath()
      ctx.arc(handleX, handleY, 3, -Math.PI * 0.7, Math.PI * 0.3)
      ctx.stroke()
      const arrowAngle = Math.PI * 0.3
      const ax = handleX + 3 * Math.cos(arrowAngle)
      const ay = handleY + 3 * Math.sin(arrowAngle)
      ctx.beginPath()
      ctx.moveTo(ax - 1.5, ay - 1.5)
      ctx.lineTo(ax, ay)
      ctx.lineTo(ax + 1.5, ay - 1)
      ctx.stroke()
    }

    ctx.restore()

    // Compute handle positions in local (un-rotated) space
    const pad = 6
    const sx = bx - pad
    const sy = by - pad
    const sw = w + pad * 2
    const sh = h + pad * 2
    const isSelected = showHandles && sticker.id === selectedId

    // Store bounds (in un-rotated local space, with rotation info for hit-testing)
    bounds.push({
      id: sticker.id,
      x: bx,
      y: by,
      width: w,
      height: h,
      size: sticker.size,
      rotation,
      centerX: cx,
      centerY: cy,
      deleteBtn: isSelected ? {
        x: sx + sw + 6,
        y: sy - 6,
        radius: 8
      } : null,
      rotationHandle: isSelected ? {
        x: sx + sw / 2,
        y: sy - 20,
        radius: 14
      } : null,
      resizeCorners: isSelected ? [
        [sx, sy], [sx + sw, sy],
        [sx, sy + sh], [sx + sw, sy + sh]
      ] : null
    })
  }

  return bounds
}

/**
 * Hit-test stickers at a canvas position.
 * Checks in reverse z-order (topmost first).
 * Returns the sticker ID if hit, or null.
 */
export function hitTestSticker(pos, stickerBounds) {
  if (!stickerBounds || stickerBounds.length === 0) return null

  const margin = 6

  // Check reverse order (topmost = last rendered = first checked)
  for (let i = stickerBounds.length - 1; i >= 0; i--) {
    const b = stickerBounds[i]

    // Un-rotate test point if sticker is rotated
    let testX = pos.x
    let testY = pos.y
    if (b.rotation && b.rotation !== 0) {
      const rad = -b.rotation * Math.PI / 180
      const cos = Math.cos(rad)
      const sin = Math.sin(rad)
      const dx = pos.x - b.centerX
      const dy = pos.y - b.centerY
      testX = b.centerX + dx * cos - dy * sin
      testY = b.centerY + dx * sin + dy * cos
    }

    if (testX >= b.x - margin && testX <= b.x + b.width + margin &&
        testY >= b.y - margin && testY <= b.y + b.height + margin) {
      return b.id
    }
  }
  return null
}

/**
 * Hit-test the delete button on the selected sticker.
 * Returns true if pos is within the delete button.
 */
export function hitTestStickerDelete(pos, stickerBounds, selectedId) {
  if (!stickerBounds || !selectedId) return false

  const b = stickerBounds.find(s => s.id === selectedId)
  if (!b || !b.deleteBtn) return false

  let testX = pos.x
  let testY = pos.y
  if (b.rotation && b.rotation !== 0) {
    const rad = -b.rotation * Math.PI / 180
    const cos = Math.cos(rad)
    const sin = Math.sin(rad)
    const dx = pos.x - b.centerX
    const dy = pos.y - b.centerY
    testX = b.centerX + dx * cos - dy * sin
    testY = b.centerY + dx * sin + dy * cos
  }

  const d = b.deleteBtn
  const dx = testX - d.x
  const dy = testY - d.y
  return Math.sqrt(dx * dx + dy * dy) < d.radius + 4
}

/**
 * Hit-test the rotation handle on the selected sticker.
 * Returns true if pos is within the rotation handle.
 */
export function hitTestStickerRotation(pos, stickerBounds, selectedId) {
  if (!stickerBounds || !selectedId) return false

  const b = stickerBounds.find(s => s.id === selectedId)
  if (!b || !b.rotationHandle) return false

  let testX = pos.x
  let testY = pos.y
  if (b.rotation && b.rotation !== 0) {
    const rad = -b.rotation * Math.PI / 180
    const cos = Math.cos(rad)
    const sin = Math.sin(rad)
    const dx = pos.x - b.centerX
    const dy = pos.y - b.centerY
    testX = b.centerX + dx * cos - dy * sin
    testY = b.centerY + dx * sin + dy * cos
  }

  const h = b.rotationHandle
  const dx = testX - h.x
  const dy = testY - h.y
  return Math.sqrt(dx * dx + dy * dy) < h.radius
}

/**
 * Hit-test the resize corner handles on the selected sticker.
 * Returns the corner index (0-3) if hit, or -1.
 */
export function hitTestStickerResize(pos, stickerBounds, selectedId) {
  if (!stickerBounds || !selectedId) return -1

  const b = stickerBounds.find(s => s.id === selectedId)
  if (!b || !b.resizeCorners) return -1

  let testX = pos.x
  let testY = pos.y
  if (b.rotation && b.rotation !== 0) {
    const rad = -b.rotation * Math.PI / 180
    const cos = Math.cos(rad)
    const sin = Math.sin(rad)
    const dx = pos.x - b.centerX
    const dy = pos.y - b.centerY
    testX = b.centerX + dx * cos - dy * sin
    testY = b.centerY + dx * sin + dy * cos
  }

  const hitRadius = 12
  for (let i = 0; i < b.resizeCorners.length; i++) {
    const [cx, cy] = b.resizeCorners[i]
    const dx = testX - cx
    const dy = testY - cy
    if (Math.sqrt(dx * dx + dy * dy) < hitRadius) {
      return i
    }
  }
  return -1
}
