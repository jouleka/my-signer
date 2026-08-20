// Device frame and screenshot rendering utilities for screenshot editor
// Extracted from screenshot_editor_controller.js for maintainability

export function roundRect(ctx, x, y, width, height, radius) {
  ctx.beginPath()
  ctx.moveTo(x + radius, y)
  ctx.lineTo(x + width - radius, y)
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius)
  ctx.lineTo(x + width, y + height - radius)
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
  ctx.lineTo(x + radius, y + height)
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius)
  ctx.lineTo(x, y + radius)
  ctx.quadraticCurveTo(x, y, x + radius, y)
  ctx.closePath()
}

export function coverFit(ctx, image, x, y, w, h) {
  const imgAspect = image.width / image.height
  const areaAspect = w / h
  let dx, dy, dw, dh

  if (imgAspect > areaAspect) {
    dh = h
    dw = dh * imgAspect
    dx = x + (w - dw) / 2
    dy = y
  } else {
    dw = w
    dh = dw / imgAspect
    dx = x
    dy = y + (h - dh) / 2
  }

  ctx.drawImage(image, dx, dy, dw, dh)
}

export function renderWithFrame(ctx, image, frameKey, padding, topSpace, availWidth, availHeight, paddingPct, framesValue, frameImageCache) {
  const frameInfo = framesValue?.[frameKey]
  const frameImg = frameImageCache.get(frameKey)

  if (!frameInfo?.vb_width || !frameImg) {
    renderWithoutFrame(ctx, image, padding, topSpace, availWidth, availHeight, paddingPct)
    return
  }

  const vbW = frameInfo.vb_width
  const vbH = frameInfo.vb_height
  const frameAspect = vbW / vbH

  let frameW, frameH
  if (paddingPct === 0) {
    if (availWidth / availHeight > frameAspect) {
      frameW = availWidth
      frameH = frameW / frameAspect
    } else {
      frameH = availHeight
      frameW = frameH * frameAspect
    }
  } else {
    if (availWidth / availHeight > frameAspect) {
      frameH = availHeight
      frameW = frameH * frameAspect
    } else {
      frameW = availWidth
      frameH = frameW / frameAspect
    }
  }

  const frameX = padding + (availWidth - frameW) / 2
  const frameY = topSpace + (availHeight - frameH) / 2
  const scale = frameW / vbW

  const sx = frameX + frameInfo.screen_x * scale
  const sy = frameY + frameInfo.screen_y * scale
  const sw = frameInfo.screen_width * scale
  const sh = frameInfo.screen_height * scale
  const srx = (frameInfo.screen_rx || 0) * scale

  if (paddingPct > 0) {
    ctx.save()
    ctx.shadowColor = "rgba(0, 0, 0, 0.35)"
    ctx.shadowBlur = frameW * 0.05
    ctx.shadowOffsetX = 0
    ctx.shadowOffsetY = frameW * 0.015
    ctx.drawImage(frameImg, frameX, frameY, frameW, frameH)
    ctx.restore()
  }
  ctx.drawImage(frameImg, frameX, frameY, frameW, frameH)

  ctx.save()
  if (srx > 0) {
    roundRect(ctx, sx, sy, sw, sh, srx)
  } else {
    ctx.beginPath()
    ctx.rect(sx, sy, sw, sh)
  }
  ctx.clip()

  const dw = sw
  const dh = sw * (image.height / image.width)
  ctx.drawImage(image, sx, sy, dw, dh)
  ctx.restore()
}

export function renderWithoutFrame(ctx, image, padding, topSpace, availWidth, availHeight, paddingPct) {
  const x = padding
  const y = topSpace

  if (paddingPct === 0) {
    coverFit(ctx, image, x, y, availWidth, availHeight)
  } else {
    const imgAspect = image.width / image.height
    const areaAspect = availWidth / availHeight
    let dx, dy, dw, dh

    if (imgAspect > areaAspect) {
      dw = availWidth
      dh = dw / imgAspect
      dx = x
      dy = y + (availHeight - dh) / 2
    } else {
      dh = availHeight
      dw = dh * imgAspect
      dx = x + (availWidth - dw) / 2
      dy = y
    }

    ctx.save()
    roundRect(ctx, dx, dy, dw, dh, 8)
    ctx.clip()
    ctx.drawImage(image, dx, dy, dw, dh)
    ctx.restore()
  }
}

export function renderScreenshot(ctx, image, canvasWidth, canvasHeight, opts, framesValue, frameImageCache) {
  const { bgType, paddingPct, captionText, captionPosition, captionMode, captionZoneSize, frameKey, screenshotOffsetY } = opts

  if (bgType === "none") {
    coverFit(ctx, image, 0, 0, canvasWidth, canvasHeight)
    return
  }

  const padding = canvasWidth * (paddingPct / 100)
  const zoneSize = (captionZoneSize || 12) / 100
  const mode = captionMode || "zone"

  let topSpace, bottomSpace
  // In zone mode, reserve caption space even when text is currently empty.
  // This keeps screenshot placement stable while typing/clearing caption text.
  if (mode === "zone") {
    if (captionPosition === "top") {
      topSpace = canvasHeight * zoneSize
      bottomSpace = padding
    } else {
      topSpace = padding
      bottomSpace = canvasHeight * zoneSize
    }
  } else {
    topSpace = padding
    bottomSpace = padding
  }

  const availWidth = canvasWidth - padding * 2
  const offsetY = canvasHeight * ((screenshotOffsetY || 0) / 100)

  // When offset is applied, size the screenshot for the full canvas (minus minimal padding)
  // so it stays large and overflows off the bottom, rather than shrinking into a smaller area.
  const baseAvailHeight = canvasHeight - topSpace - bottomSpace
  const sizeHeight = offsetY !== 0
    ? canvasHeight - padding * 2
    : baseAvailHeight

  if (frameKey && frameKey !== "none") {
    renderWithFrame(ctx, image, frameKey, padding, topSpace + offsetY, availWidth, sizeHeight, paddingPct, framesValue, frameImageCache)
  } else {
    renderWithoutFrame(ctx, image, padding, topSpace + offsetY, availWidth, sizeHeight, paddingPct)
  }
}
