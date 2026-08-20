// Caption and text rendering utilities for screenshot editor
// Extracted from screenshot_editor_controller.js for maintainability

import { segmentGraphemes, graphemeCount, isEmojiGrapheme, hasEmoji } from "lib/screenshot/emoji_utils"

export function buildFontString(weight, size, family) {
  return `${weight} ${size}px "${family}", "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`
}

export function fillTextWithSpacing(ctx, text, x, y, spacing, textAlign, opts = {}) {
  if (!spacing || spacing === 0) {
    // Even without spacing, if gradient is active we need per-grapheme control for emojis
    if (opts.gradientFillStyle && hasEmoji(text)) {
      const graphemes = segmentGraphemes(text)
      const textWidth = ctx.measureText(text).width
      let startX = x
      if (textAlign === "center") startX = x - textWidth / 2
      else if (textAlign === "right") startX = x - textWidth

      const savedAlign = ctx.textAlign
      const savedFill = ctx.fillStyle
      ctx.textAlign = "left"
      let cx = startX
      for (const g of graphemes) {
        if (isEmojiGrapheme(g)) {
          ctx.fillStyle = "#000000" // neutral fill; emoji has inherent color
        } else {
          ctx.fillStyle = opts.gradientFillStyle
        }
        ctx.fillText(g, cx, y)
        cx += ctx.measureText(g).width
      }
      ctx.textAlign = savedAlign
      ctx.fillStyle = savedFill
      return
    }
    ctx.fillText(text, x, y)
    return
  }

  const graphemes = segmentGraphemes(text)
  const count = graphemes.length
  const totalExtra = (count - 1) * spacing
  const textWidth = ctx.measureText(text).width + totalExtra

  let startX = x
  if (textAlign === "center") {
    startX = x - textWidth / 2
  } else if (textAlign === "right") {
    startX = x - textWidth
  }

  const savedAlign = ctx.textAlign
  const savedFill = ctx.fillStyle
  ctx.textAlign = "left"
  let cx = startX
  for (const g of graphemes) {
    if (opts.gradientFillStyle && isEmojiGrapheme(g)) {
      ctx.fillStyle = "#000000"
    } else if (opts.gradientFillStyle) {
      ctx.fillStyle = opts.gradientFillStyle
    }
    ctx.fillText(g, cx, y)
    cx += ctx.measureText(g).width + spacing
  }
  ctx.textAlign = savedAlign
  ctx.fillStyle = savedFill
}

export function strokeTextWithSpacing(ctx, text, x, y, spacing, textAlign) {
  if (!spacing || spacing === 0) {
    // If text contains emojis, stroke per-grapheme skipping emojis
    if (hasEmoji(text)) {
      const graphemes = segmentGraphemes(text)
      const textWidth = ctx.measureText(text).width
      let startX = x
      if (textAlign === "center") startX = x - textWidth / 2
      else if (textAlign === "right") startX = x - textWidth

      const savedAlign = ctx.textAlign
      ctx.textAlign = "left"
      let cx = startX
      for (const g of graphemes) {
        if (!isEmojiGrapheme(g)) {
          ctx.strokeText(g, cx, y)
        }
        cx += ctx.measureText(g).width
      }
      ctx.textAlign = savedAlign
      return
    }
    ctx.strokeText(text, x, y)
    return
  }

  const graphemes = segmentGraphemes(text)
  const count = graphemes.length
  const totalExtra = (count - 1) * spacing
  const textWidth = ctx.measureText(text).width + totalExtra

  let startX = x
  if (textAlign === "center") {
    startX = x - textWidth / 2
  } else if (textAlign === "right") {
    startX = x - textWidth
  }

  const savedAlign = ctx.textAlign
  ctx.textAlign = "left"
  let cx = startX
  for (const g of graphemes) {
    if (!isEmojiGrapheme(g)) {
      ctx.strokeText(g, cx, y)
    }
    cx += ctx.measureText(g).width + spacing
  }
  ctx.textAlign = savedAlign
}

export function measureTextWithSpacing(ctx, text, spacing) {
  const base = ctx.measureText(text).width
  if (!spacing || spacing === 0) return base
  return base + (graphemeCount(text) - 1) * spacing
}

export function wrapText(ctx, text, maxWidth) {
  const words = text.split(" ")
  const lines = []
  let currentLine = words[0] || ""

  for (let i = 1; i < words.length; i++) {
    const testLine = currentLine + " " + words[i]
    if (ctx.measureText(testLine).width > maxWidth) {
      lines.push(currentLine)
      currentLine = words[i]
    } else {
      currentLine = testLine
    }
  }
  lines.push(currentLine)
  return lines
}

export function drawTextBackgroundPill(ctx, x, y, totalWidth, totalHeight, opts, scale, roundRectFn) {
  if (!opts.textBgEnabled) return

  const padX = opts.textBgPaddingX * scale
  const padY = opts.textBgPaddingY * scale
  const radius = opts.textBgRadius * scale

  const rx = x - padX
  const ry = y - padY
  const rw = totalWidth + padX * 2
  const rh = totalHeight + padY * 2

  ctx.save()
  ctx.globalAlpha = opts.textBgOpacity / 100
  ctx.fillStyle = opts.textBgColor
  ctx.beginPath()
  if (ctx.roundRect) {
    ctx.roundRect(rx, ry, rw, rh, radius)
  } else {
    roundRectFn(ctx, rx, ry, rw, rh, radius)
  }
  ctx.fill()
  ctx.restore()
}

export function drawStyledText(ctx, lines, x, startY, lineHeight, fontSize, opts) {
  const scale = ctx.canvas.width / 1080
  const spacing = (opts.letterSpacing || 0) * scale

  // Set up gradient fill if enabled
  let gradientFillStyle = null
  if (opts.gradientEnabled) {
    const totalHeight = lines.length * lineHeight
    const gradient = ctx.createLinearGradient(x - ctx.canvas.width * 0.4, startY, x + ctx.canvas.width * 0.4, startY + totalHeight)
    gradient.addColorStop(0, opts.gradientStart)
    gradient.addColorStop(1, opts.gradientEnd)
    ctx.fillStyle = gradient
    gradientFillStyle = gradient
  }

  lines.forEach((line, i) => {
    const ly = startY + i * lineHeight

    // Stroke (skips emoji graphemes automatically)
    if (opts.strokeEnabled) {
      ctx.save()
      ctx.strokeStyle = opts.strokeColor
      ctx.lineWidth = opts.strokeWidth * scale
      ctx.lineJoin = "round"
      strokeTextWithSpacing(ctx, line, x, ly, spacing, opts.textAlign || "center")
      ctx.restore()
    }

    // Fill (preserves emoji color when gradient is active)
    fillTextWithSpacing(ctx, line, x, ly, spacing, opts.textAlign || "center", { gradientFillStyle })
  })
}

/**
 * Render the full caption group (title + subtitle) onto the canvas.
 * Returns { textBounds, resizeHandles } for hit-testing.
 */
export function renderCaptionGroup(ctx, canvasWidth, canvasHeight, opts, roundRectFn) {
  const hasTitle = opts.text && opts.text.trim()
  const hasSubtitle = opts.subtitleText && opts.subtitleText.trim()
  if (!hasTitle && !hasSubtitle) return { textBounds: null, resizeHandles: null }

  const scale = canvasWidth / 1080
  const mode = opts.mode || "zone"

  // Title measurement
  const titleFontSize = Math.round(opts.fontSize * scale)
  const titleFont = buildFontString(opts.fontWeight || 700, titleFontSize, opts.fontFamily || "Inter")
  const titleLineHeight = titleFontSize * (opts.lineHeight || 1.3)

  // Subtitle measurement
  const subtitleFontSize = Math.round((opts.subtitleFontSize || 20) * scale)
  const subtitleFont = buildFontString(opts.subtitleFontWeight || 400, subtitleFontSize, opts.subtitleFontFamily || "Inter")
  const subtitleLineHeight = subtitleFontSize * (opts.subtitleLineHeight || 1.3)

  const textAlign = opts.textAlign || "center"
  const maxWidth = canvasWidth * 0.85

  // Wrap title
  ctx.font = titleFont
  ctx.textAlign = textAlign
  ctx.textBaseline = "middle"
  const titleLines = hasTitle ? wrapText(ctx, opts.text, maxWidth) : []
  const titleBlockHeight = titleLines.length * titleLineHeight

  // Wrap subtitle
  ctx.font = subtitleFont
  const subtitleLines = hasSubtitle ? wrapText(ctx, opts.subtitleText, maxWidth) : []
  const subtitleBlockHeight = subtitleLines.length * subtitleLineHeight

  // Gap between title and subtitle
  const gap = hasTitle && hasSubtitle ? titleFontSize * 0.3 : 0
  const totalTextHeight = titleBlockHeight + gap + subtitleBlockHeight

  // Determine X position based on alignment
  let textX
  if (textAlign === "left") {
    textX = canvasWidth * 0.075
  } else if (textAlign === "right") {
    textX = canvasWidth * 0.925
  } else {
    textX = canvasWidth / 2
  }

  // Measure max line width for text bounds
  let maxLineWidth = 0
  ctx.font = titleFont
  const titleSpacingMeasure = (opts.letterSpacing || 0) * scale
  titleLines.forEach(line => {
    const w = measureTextWithSpacing(ctx, line, titleSpacingMeasure)
    if (w > maxLineWidth) maxLineWidth = w
  })
  ctx.font = subtitleFont
  const subtitleSpacingMeasure = (opts.subtitleLetterSpacing || 0) * scale
  subtitleLines.forEach(line => {
    const w = measureTextWithSpacing(ctx, line, subtitleSpacingMeasure)
    if (w > maxLineWidth) maxLineWidth = w
  })

  // Determine Y position
  let startY
  const hasDragPos = opts.dragPositionX != null && opts.dragPositionY != null
  const vp = opts.verticalPosition
  const hasVP = vp !== "" && vp !== null && vp !== undefined && !isNaN(parseFloat(vp))

  if (hasDragPos) {
    const strokeBleed = opts.strokeEnabled ? ((opts.strokeWidth || 2) * scale) : 0
    const shadowBleedX = titleFontSize * 0.15 + strokeBleed
    const shadowBleedY = titleFontSize * 0.22 + strokeBleed
    const edgePadX = Math.max(canvasWidth * 0.01, shadowBleedX, 6 * scale)
    const edgePadY = Math.max(canvasHeight * 0.01, shadowBleedY, 6 * scale)

    const clampAxis = (value, halfSize, totalSize, edgePad = 0) => {
      if (!Number.isFinite(totalSize) || totalSize <= 0) return 0
      if (!Number.isFinite(value)) return totalSize / 2
      if (!Number.isFinite(halfSize)) return totalSize / 2
      const min = halfSize + edgePad
      const max = totalSize - halfSize - edgePad
      if (min >= max) return totalSize / 2
      return Math.max(min, Math.min(max, value))
    }

    const dragXPct = parseFloat(opts.dragPositionX)
    const dragYPct = parseFloat(opts.dragPositionY)
    const requestedCenterX = canvasWidth * ((Number.isFinite(dragXPct) ? dragXPct : 50) / 100)
    const requestedCenterY = canvasHeight * ((Number.isFinite(dragYPct) ? dragYPct : 50) / 100)
    const halfWidth = maxLineWidth / 2
    const halfHeight = totalTextHeight / 2

    const clampedCenterX = clampAxis(requestedCenterX, halfWidth, canvasWidth, edgePadX)
    const clampedCenterY = clampAxis(requestedCenterY, halfHeight, canvasHeight, edgePadY)

    if (textAlign === "left") {
      textX = clampedCenterX - halfWidth
    } else if (textAlign === "right") {
      textX = clampedCenterX + halfWidth
    } else {
      textX = clampedCenterX
    }

    startY = clampedCenterY - totalTextHeight / 2 + titleLineHeight / 2
  } else if (hasVP) {
    const vpPct = parseFloat(vp) / 100
    startY = canvasHeight * vpPct - totalTextHeight / 2 + titleLineHeight / 2
    startY = Math.max(titleLineHeight / 2, Math.min(startY, canvasHeight - totalTextHeight + titleLineHeight / 2))
  } else if (mode === "zone") {
    const edgePad = canvasHeight * 0.02
    if (opts.position === "top") {
      // Pin text near the top of the canvas; zone defines where the screenshot starts
      startY = edgePad + titleLineHeight / 2
    } else {
      // Pin text near the bottom of the canvas
      startY = canvasHeight - edgePad - totalTextHeight + titleLineHeight / 2
    }
  } else {
    if (opts.position === "top") {
      startY = canvasHeight * 0.08 + titleLineHeight / 2
    } else {
      startY = canvasHeight * 0.92 - totalTextHeight + titleLineHeight / 2
    }
  }

  // Calculate text bounds (before rotation)
  let boundsX
  if (textAlign === "left") {
    boundsX = textX
  } else if (textAlign === "right") {
    boundsX = textX - maxLineWidth
  } else {
    boundsX = textX - maxLineWidth / 2
  }
  const boundsY = startY - titleLineHeight / 2

  // Rotation setup
  const rotation = opts.rotation || 0
  const rotationRad = rotation * Math.PI / 180
  const centerX = boundsX + maxLineWidth / 2
  const centerY = boundsY + totalTextHeight / 2

  // Apply rotation transform
  if (rotation !== 0) {
    ctx.save()
    ctx.translate(centerX, centerY)
    ctx.rotate(rotationRad)
    ctx.translate(-centerX, -centerY)
  }

  // Text background pill
  if (opts.textBgEnabled) {
    let pillX
    if (textAlign === "left") {
      pillX = textX
    } else if (textAlign === "right") {
      pillX = textX - maxLineWidth
    } else {
      pillX = textX - maxLineWidth / 2
    }
    const pillY = startY - titleLineHeight / 2

    drawTextBackgroundPill(ctx, pillX, pillY, maxLineWidth, totalTextHeight, opts, scale, roundRectFn)
  }

  // Shadow
  ctx.shadowColor = "rgba(0, 0, 0, 0.5)"
  ctx.shadowBlur = titleFontSize * 0.15
  ctx.shadowOffsetX = 0
  ctx.shadowOffsetY = titleFontSize * 0.05

  // Draw title
  if (hasTitle) {
    ctx.font = titleFont
    ctx.fillStyle = opts.color || "#FFFFFF"
    ctx.textAlign = textAlign
    ctx.textBaseline = "middle"

    drawStyledText(ctx, titleLines, textX, startY, titleLineHeight, titleFontSize, {
      letterSpacing: opts.letterSpacing || 0,
      strokeEnabled: opts.strokeEnabled,
      strokeColor: opts.strokeColor,
      strokeWidth: opts.strokeWidth,
      gradientEnabled: opts.gradientEnabled,
      gradientStart: opts.gradientStart,
      gradientEnd: opts.gradientEnd,
      textAlign
    })
  }

  // Draw subtitle
  if (hasSubtitle) {
    const subtitleStartY = startY + titleBlockHeight + gap
    ctx.font = subtitleFont
    ctx.fillStyle = opts.subtitleColor || "#CCCCCC"
    ctx.textAlign = textAlign
    ctx.textBaseline = "middle"

    ctx.shadowBlur = subtitleFontSize * 0.1

    drawStyledText(ctx, subtitleLines, textX, subtitleStartY, subtitleLineHeight, subtitleFontSize, {
      letterSpacing: opts.subtitleLetterSpacing || 0,
      strokeEnabled: opts.strokeEnabled,
      strokeColor: opts.strokeColor,
      strokeWidth: opts.strokeWidth,
      gradientEnabled: false,
      textAlign
    })
  }

  // Reset shadow
  ctx.shadowColor = "transparent"
  ctx.shadowBlur = 0
  ctx.shadowOffsetX = 0
  ctx.shadowOffsetY = 0

  // Draw bounding box, resize handles, and rotation handle in freeform mode
  let resizeHandles = null
  let rotationHandle = null
  if (opts.showHandles) {
    ctx.save()
    ctx.strokeStyle = "rgba(99, 102, 241, 0.5)"
    ctx.lineWidth = 1.5
    ctx.setLineDash([4, 4])

    const bx = boundsX - 8
    const by = boundsY - 8
    const bw = maxLineWidth + 16
    const bh = totalTextHeight + 16
    ctx.strokeRect(bx, by, bw, bh)

    ctx.setLineDash([])
    ctx.fillStyle = "rgba(99, 102, 241, 0.9)"
    const hr = 4
    const corners = [[bx, by], [bx + bw, by], [bx, by + bh], [bx + bw, by + bh]]
    corners.forEach(([cx, cy]) => {
      ctx.beginPath()
      ctx.arc(cx, cy, hr, 0, Math.PI * 2)
      ctx.fill()
    })

    // Rotation handle: stem from top-center upward + circle
    const stemLength = 24
    const topCenterX = bx + bw / 2
    const topCenterY = by
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

    // Small arc arrow icon inside the rotation handle
    ctx.strokeStyle = "#FFFFFF"
    ctx.lineWidth = 1.2
    ctx.beginPath()
    ctx.arc(handleX, handleY, 3, -Math.PI * 0.7, Math.PI * 0.3)
    ctx.stroke()
    // Arrowhead
    const arrowAngle = Math.PI * 0.3
    const ax = handleX + 3 * Math.cos(arrowAngle)
    const ay = handleY + 3 * Math.sin(arrowAngle)
    ctx.beginPath()
    ctx.moveTo(ax - 1.5, ay - 1.5)
    ctx.lineTo(ax, ay)
    ctx.lineTo(ax + 1.5, ay - 1)
    ctx.stroke()

    // Store rotation handle in local coords (will be transformed below)
    rotationHandle = { x: handleX, y: handleY }

    resizeHandles = corners
    ctx.restore()
  }

  // Restore rotation transform
  if (rotation !== 0) {
    ctx.restore()
  }

  // Transform coordinates to canvas space when rotated
  function rotatePoint(px, py) {
    if (rotation === 0) return [px, py]
    const cos = Math.cos(rotationRad)
    const sin = Math.sin(rotationRad)
    const dx = px - centerX
    const dy = py - centerY
    return [centerX + dx * cos - dy * sin, centerY + dx * sin + dy * cos]
  }

  if (resizeHandles && rotation !== 0) {
    resizeHandles = resizeHandles.map(([px, py]) => rotatePoint(px, py))
  }

  if (rotationHandle && rotation !== 0) {
    const [rx, ry] = rotatePoint(rotationHandle.x, rotationHandle.y)
    rotationHandle = { x: rx, y: ry }
  }

  const textBounds = {
    x: boundsX,
    y: boundsY,
    width: maxLineWidth,
    height: totalTextHeight,
    canvasWidth,
    canvasHeight,
    rotation,
    centerX,
    centerY
  }

  return { textBounds, resizeHandles, rotationHandle }
}
