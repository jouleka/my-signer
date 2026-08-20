// perspective_renderer.js — Fake 3D perspective via affine-transform strip rendering (Canvas 2D)

export const PERSPECTIVE_PRESETS = {
  none:         { label: "None",         rotateX: 0,   rotateY: 0,   distance: 2000 },
  slight_left:  { label: "Slight Left",  rotateX: 0,   rotateY: 12,  distance: 2000 },
  slight_right: { label: "Slight Right", rotateX: 0,   rotateY: -12, distance: 2000 },
  left_tilt:    { label: "Left Tilt",    rotateX: 5,   rotateY: 25,  distance: 2000 },
  right_tilt:   { label: "Right Tilt",   rotateX: 5,   rotateY: -25, distance: 2000 },
  top_down:     { label: "Top Down",     rotateX: 20,  rotateY: 0,   distance: 2000 },
  bottom_up:    { label: "Bottom Up",    rotateX: -20, rotateY: 0,   distance: 2000 },
  hero_left:    { label: "Hero Left",    rotateX: 8,   rotateY: 30,  distance: 2000 },
  hero_right:   { label: "Hero Right",   rotateX: 8,   rotateY: -30, distance: 2000 },
  showcase:     { label: "Showcase",     rotateX: 12,  rotateY: -20, distance: 2000 },
  isometric:    { label: "Isometric",    rotateX: 18,  rotateY: 22,  distance: 2000 },
  flat_lay:     { label: "Flat Lay",     rotateX: 35,  rotateY: 0,   distance: 2000 }
}

/**
 * Project 4 corners of a rectangle through 3D rotation + perspective division.
 * Returns [{x,y}, {x,y}, {x,y}, {x,y}] — TL, TR, BR, BL in normalised coords
 * centred at (0,0) where the source rect spans -w/2..+w/2, -h/2..+h/2.
 */
export function computePerspectiveQuad(w, h, rotateXDeg, rotateYDeg, perspectiveDist) {
  const toRad = Math.PI / 180
  const ax = rotateXDeg * toRad
  const ay = rotateYDeg * toRad

  const cosX = Math.cos(ax), sinX = Math.sin(ax)
  const cosY = Math.cos(ay), sinY = Math.sin(ay)

  // 4 corners in 3D (centred at origin)
  const corners3D = [
    { x: -w / 2, y: -h / 2, z: 0 }, // TL
    { x:  w / 2, y: -h / 2, z: 0 }, // TR
    { x:  w / 2, y:  h / 2, z: 0 }, // BR
    { x: -w / 2, y:  h / 2, z: 0 }  // BL
  ]

  // Apply rotateY then rotateX (same order as CSS perspective())
  const rotated = corners3D.map(({ x, y, z }) => {
    // Rotate around Y axis
    const x1 = x * cosY + z * sinY
    const z1 = -x * sinY + z * cosY
    // Rotate around X axis
    const y2 = y * cosX - z1 * sinX
    const z2 = y * sinX + z1 * cosX
    return { x: x1, y: y2, z: z2 }
  })

  // Perspective projection
  const d = perspectiveDist
  return rotated.map(({ x, y, z }) => {
    const scale = d / (d + z)
    return { x: x * scale, y: y * scale }
  })
}

/**
 * Inverse bilinear interpolation: given a screen point (px, py) and the four
 * transformed corners tQuad [TL, TR, BR, BL], find the corresponding source
 * canvas coordinates. Returns {x, y} in source space or null if outside the quad.
 *
 * Math: P = A + B*u + C*v + D*u*v where
 *   A = TL, B = TR - TL, C = BL - TL, D = TL - TR + BR - BL
 * Solve for (u, v) in [0,1]x[0,1], then map to source coords.
 */
export function inversePerspectivePoint(px, py, tQuad, srcW, srcH) {
  const [tl, tr, br, bl] = tQuad

  const ax = tl.x, ay = tl.y
  const bx = tr.x - tl.x, by = tr.y - tl.y
  const cx = bl.x - tl.x, cy = bl.y - tl.y
  const dx = tl.x - tr.x + br.x - bl.x, dy = tl.y - tr.y + br.y - bl.y

  // Translate point relative to A
  const ex = px - ax, ey = py - ay

  // Solve: ex = bx*u + cx*v + dx*u*v
  //        ey = by*u + cy*v + dy*u*v
  // Eliminate v: from first eq, v = (ex - bx*u) / (cx + dx*u)
  // Substitute into second → quadratic in u

  let u, v

  // Quadratic coefficients: alpha*u^2 + beta*u + gamma = 0
  // Derived by substituting v = (ex - bx*u)/(cx + dx*u) into the second equation
  // and multiplying through by (cx + dx*u)
  const alpha = by * dx - bx * dy
  const beta  = by * cx - bx * cy + dy * ex - dx * ey
  const gamma = cy * ex - cx * ey

  // Small tolerance for edge clicks
  const tol = 0.02

  if (Math.abs(alpha) < 1e-10) {
    // Degenerate (parallelogram) — linear in u
    if (Math.abs(beta) < 1e-10) return null
    u = -gamma / beta
  } else {
    const disc = beta * beta - 4 * alpha * gamma
    if (disc < 0) return null

    const sqrtDisc = Math.sqrt(disc)
    const u1 = (-beta + sqrtDisc) / (2 * alpha)
    const u2 = (-beta - sqrtDisc) / (2 * alpha)

    // Pick the root in [0,1] (with tolerance)
    const ok1 = u1 >= -tol && u1 <= 1 + tol
    const ok2 = u2 >= -tol && u2 <= 1 + tol
    if (ok1 && ok2) {
      // Both in range — pick the one closer to [0,1] center
      u = (Math.abs(u1 - 0.5) <= Math.abs(u2 - 0.5)) ? u1 : u2
    } else if (ok1) {
      u = u1
    } else if (ok2) {
      u = u2
    } else {
      return null
    }
  }

  // Back-substitute for v
  const denom = cx + dx * u
  if (Math.abs(denom) < 1e-10) {
    // Try the other equation
    const denom2 = cy + dy * u
    if (Math.abs(denom2) < 1e-10) return null
    v = (ey - by * u) / denom2
  } else {
    v = (ex - bx * u) / denom
  }

  // Check bounds with tolerance
  if (u < -tol || u > 1 + tol || v < -tol || v > 1 + tol) return null

  // Clamp to [0,1]
  u = Math.max(0, Math.min(1, u))
  v = Math.max(0, Math.min(1, v))

  return { x: u * srcW, y: v * srcH }
}

/**
 * Render sourceCanvas onto ctx with perspective transformation using affine-transform strip slicing.
 *
 * opts: {
 *   rotateX, rotateY, distance,     // perspective params
 *   shadow: bool,                    // draw floor shadow
 *   reflection: bool                 // draw faded reflection below
 * }
 */
export function renderWithPerspective(ctx, sourceCanvas, canvasWidth, canvasHeight, opts) {
  const { rotateX = 0, rotateY = 0, distance = 2000, shadow = false, reflection = false, quality = "full" } = opts
  const isDraft = quality === "draft"

  const srcW = sourceCanvas.width
  const srcH = sourceCanvas.height

  // Compute destination quad
  const quad = computePerspectiveQuad(srcW, srcH, rotateX, rotateY, distance)

  // Find bounding box of quad
  const xs = quad.map(p => p.x)
  const ys = quad.map(p => p.y)
  const minX = Math.min(...xs), maxX = Math.max(...xs)
  const minY = Math.min(...ys), maxY = Math.max(...ys)
  const quadW = maxX - minX
  const quadH = maxY - minY

  // Scale to fit within canvas with margin
  const margin = 0.06
  const availW = canvasWidth * (1 - margin * 2)
  const availH = canvasHeight * (1 - margin * 2)
  const fitScale = Math.min(availW / quadW, availH / quadH)

  // Centre offset
  const cx = canvasWidth / 2
  const cy = canvasHeight / 2

  // Transform quad points to canvas coords
  const tQuad = quad.map(p => ({
    x: cx + p.x * fitScale,
    y: cy + p.y * fitScale
  }))

  // TL=0, TR=1, BR=2, BL=3

  // --- Shadow ---
  if (shadow) {
    _drawShadow(ctx, tQuad, canvasWidth, canvasHeight)
  }

  // --- Strip-based rendering using affine transforms ---
  // Use enough strips for smooth rendering: ~1 strip per 2 source pixels, min 80
  // Draft mode uses fewer strips (30-60) for faster interaction rendering
  const absAngle = Math.abs(rotateX) + Math.abs(rotateY)
  const cores = (typeof navigator !== "undefined" && navigator.hardwareConcurrency) ? navigator.hardwareConcurrency : 8
  const lowPowerDevice = cores <= 4
  let numStrips
  if (isDraft) {
    numStrips = absAngle < 3 ? 120 : Math.max(160, Math.min(280, Math.round(canvasHeight * 0.45)))
  } else {
    if (absAngle < 3) {
      numStrips = Math.max(120, Math.round(srcH / 3))
    } else {
      // Cap strips so quality remains high without burning CPU on very high internal resolutions.
      const maxStrips = lowPowerDevice ? 320 : 520
      numStrips = Math.max(220, Math.min(maxStrips, Math.round(canvasHeight * 0.55)))
    }
  }

  _drawStrips(ctx, sourceCanvas, tQuad, srcW, srcH, numStrips)

  // --- Reflection ---
  if (reflection) {
    _drawReflection(ctx, sourceCanvas, tQuad, srcW, srcH, canvasHeight, isDraft)
  }

  return tQuad
}

/**
 * Draw the source canvas onto ctx using affine-transform per horizontal strip.
 *
 * For each thin strip, we compute an affine transform (via setTransform) that maps
 * the source strip rectangle to the destination parallelogram. For thin enough strips,
 * this is visually identical to true perspective since the difference between a
 * trapezoid and a parallelogram is negligible at ~1-2px height.
 *
 * tQuad: [TL, TR, BR, BL] in canvas coordinates.
 */
function _drawStrips(ctx, sourceCanvas, tQuad, srcW, srcH, numStrips) {
  const [tl, tr, br, bl] = tQuad

  for (let i = 0; i < numStrips; i++) {
    const t0 = i / numStrips
    const t1 = (i + 1) / numStrips

    // Four corners of this strip in destination space
    const dTL = _lerp2D(tl, bl, t0)
    const dTR = _lerp2D(tr, br, t0)
    const dBL = _lerp2D(tl, bl, t1)

    // Source strip: full width, vertical slice from sy to sy+sh
    const sy = t0 * srcH
    const sh = (t1 - t0) * srcH
    if (sh < 0.001) continue

    // Compute affine transform that maps:
    //   source (0, 0) → destination dTL
    //   source (srcW, 0) → destination dTR
    //   source (0, sh) → destination dBL
    //
    // Transform matrix: x' = a*x + c*y + e,  y' = b*x + d*y + f
    const a = (dTR.x - dTL.x) / srcW
    const b = (dTR.y - dTL.y) / srcW
    const c = (dBL.x - dTL.x) / sh
    const d = (dBL.y - dTL.y) / sh
    const e = dTL.x
    const f = dTL.y

    ctx.save()
    ctx.setTransform(a, b, c, d, e, f)
    ctx.imageSmoothingEnabled = true
    ctx.imageSmoothingQuality = "high"

    // Use sub-pixel sampling and generous overlap to avoid visible seams/banding.
    // Scale overlap with strip height so thicker strips (fewer strips) still blend seamlessly.
    const overlap = Math.max(2.0, sh * 0.35)
    const srcSliceY = Math.max(0, sy - overlap / 2)
    const srcSliceH = Math.min(srcH - srcSliceY, sh + overlap)
    const dstY = -overlap / 2
    const dstH = sh + overlap

    ctx.drawImage(sourceCanvas, 0, srcSliceY, srcW, srcSliceH, 0, dstY, srcW, dstH)

    ctx.restore()
  }
}

/**
 * Draw a soft shadow below the perspective quad.
 */
function _drawShadow(ctx, tQuad, canvasWidth, canvasHeight) {
  const [tl, tr, br, bl] = tQuad

  const bottomY = Math.max(br.y, bl.y)
  const shadowOffset = canvasHeight * 0.02
  const shadowHeight = canvasHeight * 0.06

  ctx.save()

  const shadowQuad = [
    { x: bl.x + (bl.x - tl.x) * 0.15, y: bottomY + shadowOffset },
    { x: br.x + (br.x - tr.x) * 0.15, y: bottomY + shadowOffset },
    { x: br.x + (br.x - tr.x) * 0.3,  y: bottomY + shadowOffset + shadowHeight },
    { x: bl.x + (bl.x - tl.x) * 0.3,  y: bottomY + shadowOffset + shadowHeight }
  ]

  ctx.beginPath()
  ctx.moveTo(shadowQuad[0].x, shadowQuad[0].y)
  ctx.lineTo(shadowQuad[1].x, shadowQuad[1].y)
  ctx.lineTo(shadowQuad[2].x, shadowQuad[2].y)
  ctx.lineTo(shadowQuad[3].x, shadowQuad[3].y)
  ctx.closePath()

  ctx.filter = `blur(${Math.round(canvasHeight * 0.02)}px)`
  ctx.fillStyle = "rgba(0,0,0,0.25)"
  ctx.fill()

  ctx.restore()
}

/**
 * Draw a faded reflection below the perspective quad using affine strips.
 */
function _drawReflection(ctx, sourceCanvas, tQuad, srcW, srcH, canvasHeight, isDraft = false) {
  const [tl, tr, br, bl] = tQuad

  const reflectionHeight = Math.abs(br.y - tr.y) * 0.35
  const reflStrips = isDraft
    ? Math.max(8, Math.round(reflectionHeight * 0.3))
    : Math.max(20, Math.round(reflectionHeight))

  for (let i = 0; i < reflStrips; i++) {
    const t = i / reflStrips
    const t1 = (i + 1) / reflStrips

    // Source: sample from bottom of image going upward
    const srcFrac = t * 0.35
    const srcY = Math.floor(srcH * (1 - srcFrac) - 1)
    const srcSliceH = Math.max(1, Math.ceil(srcH * 0.35 / reflStrips))

    // Destination: below the quad bottom, going downward
    const spreadFactor = 0.1
    const dTL = { x: _lerp(bl.x, bl.x + (bl.x - tl.x) * spreadFactor, t),  y: bl.y + t  * reflectionHeight }
    const dTR = { x: _lerp(br.x, br.x + (br.x - tr.x) * spreadFactor, t),  y: br.y + t  * reflectionHeight }
    const dBL = { x: _lerp(bl.x, bl.x + (bl.x - tl.x) * spreadFactor, t1), y: bl.y + t1 * reflectionHeight }

    const sh = Math.max(0.5, dBL.y - dTL.y)

    const a = (dTR.x - dTL.x) / srcW
    const b = (dTR.y - dTL.y) / srcW
    const c = (dBL.x - dTL.x) / sh
    const d = (dBL.y - dTL.y) / sh
    const e = dTL.x
    const f = dTL.y

    ctx.save()
    ctx.globalAlpha = 0.15 * (1 - t)
    ctx.setTransform(a, b, c, d, e, f)
    ctx.drawImage(sourceCanvas, 0, Math.max(0, srcY), srcW, srcSliceH, 0, 0, srcW, sh)
    ctx.restore()
  }
}

function _lerp(a, b, t) {
  return a + (b - a) * t
}

function _lerp2D(a, b, t) {
  return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t }
}
