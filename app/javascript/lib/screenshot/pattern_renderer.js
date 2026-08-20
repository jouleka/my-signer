// Pattern renderer — SVG tile patterns + procedural patterns for screenshot backgrounds

const patternCache = new Map()  // cacheKey -> CanvasPattern
const imageCache = new Map()    // cacheKey -> HTMLImageElement
const pendingLoads = new Map()  // cacheKey -> Promise
const failedLoads = new Set()   // cacheKey -> failed to load; avoid retry loops
const MAX_CACHE_SIZE = 100

const PROCEDURAL_PATTERNS = new Set(["perlin_noise", "confetti", "topography"])

// Cache for procedural pattern renders (deterministic output, expensive to compute)
const proceduralCache = new Map()
const MAX_PROCEDURAL_CACHE = 10

function proceduralCacheKey(patternId, color, scale, width, height) {
  return `${patternId}_${color}_${scale}_${width}_${height}`
}

export function isProceduralPattern(patternId) {
  return PROCEDURAL_PATTERNS.has(patternId)
}

function cacheKey(patternId, color, scale) {
  return `${patternId}_${color}_${scale}`
}

function evictIfNeeded() {
  if (patternCache.size <= MAX_CACHE_SIZE) return
  const keys = Array.from(patternCache.keys())
  for (let i = 0; i < keys.length - MAX_CACHE_SIZE; i++) {
    patternCache.delete(keys[i])
    imageCache.delete(keys[i])
  }
}

/**
 * Get a cached CanvasPattern if available (sync, for preview path).
 */
export function getCachedPattern(ctx, patternId, color, scale) {
  const key = cacheKey(patternId, color, scale)
  return patternCache.get(key) || null
}

/**
 * Ensure a tile pattern is loaded and cached. Returns a promise.
 * For procedural patterns, this is a no-op (they render directly).
 */
export async function ensurePatternLoaded(ctx, patternId, color, scale, patternLibrary) {
  if (isProceduralPattern(patternId)) return true

  const key = cacheKey(patternId, color, scale)
  if (patternCache.has(key)) return true
  if (failedLoads.has(key)) return false

  if (pendingLoads.has(key)) {
    await pendingLoads.get(key)
    return patternCache.has(key)
  }

  const promise = _loadTilePattern(ctx, patternId, color, scale, patternLibrary)
  pendingLoads.set(key, promise)
  try {
    const loaded = await promise
    if (!loaded) failedLoads.add(key)
    return loaded
  } finally {
    pendingLoads.delete(key)
  }
}

async function _loadTilePattern(ctx, patternId, color, scale, patternLibrary) {
  const key = cacheKey(patternId, color, scale)

  // Find the SVG URL from the pattern library
  let svgUrl = null
  if (patternLibrary) {
    const tiles = patternLibrary.tiles || []
    const entry = tiles.find(t => t.id === patternId)
    if (entry) svgUrl = entry.image_url
  }
  if (!svgUrl) {
    console.warn(`Pattern tile URL missing: ${patternId}`)
    return false
  }

  try {
    const response = await fetch(svgUrl)
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} for ${svgUrl}`)
    }
    let svgText = await response.text()
    if (!/<svg[\s>]/i.test(svgText)) {
      throw new Error(`Unexpected non-SVG response for ${svgUrl}`)
    }

    // Recolor: replace currentColor with the actual color
    svgText = svgText.replace(/currentColor/g, color)

    // Apply scale by adjusting the viewBox/dimensions
    const scaleMultiplier = (scale || 100) / 100

    // Create blob URL from the recolored SVG
    const blob = new Blob([svgText], { type: "image/svg+xml" })
    const blobUrl = URL.createObjectURL(blob)

    const img = new Image()
    try {
      await new Promise((resolve, reject) => {
        img.onload = resolve
        img.onerror = reject
        img.src = blobUrl
      })
    } finally {
      URL.revokeObjectURL(blobUrl)
    }

    // Create a scaled canvas for the tile
    const tileW = Math.max(1, Math.round(img.width * scaleMultiplier))
    const tileH = Math.max(1, Math.round(img.height * scaleMultiplier))
    const tileCanvas = document.createElement("canvas")
    tileCanvas.width = tileW
    tileCanvas.height = tileH
    const tileCtx = tileCanvas.getContext("2d")
    tileCtx.drawImage(img, 0, 0, tileW, tileH)

    const pattern = ctx.createPattern(tileCanvas, "repeat")
    if (!pattern) {
      throw new Error(`createPattern returned null for ${patternId}`)
    }
    patternCache.set(key, pattern)
    imageCache.set(key, tileCanvas)
    failedLoads.delete(key)
    evictIfNeeded()
    return true
  } catch (e) {
    console.warn(`Failed to load pattern tile: ${patternId}`, e)
    return false
  }
}

/**
 * Render a pattern on the canvas context.
 *
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} width
 * @param {number} height
 * @param {string} patternId
 * @param {object} options - { color, bgColor, scale, patternLibrary }
 */
export function renderPattern(ctx, width, height, patternId, options = {}) {
  const { color = "#FFFFFF", bgColor = "#000000", scale = 100, patternLibrary } = options

  // Fill background color first
  ctx.fillStyle = bgColor
  ctx.fillRect(0, 0, width, height)

  if (isProceduralPattern(patternId)) {
    _renderProceduralPattern(ctx, width, height, patternId, color, scale)
    return
  }

  // Try sync cached tile pattern
  const key = cacheKey(patternId, color, scale)
  const cached = patternCache.get(key)
  if (cached) {
    ctx.fillStyle = cached
    ctx.fillRect(0, 0, width, height)
    return
  }

  // If not cached, start async load and trigger re-render via callback when ready
  ensurePatternLoaded(ctx, patternId, color, scale, patternLibrary).then((loaded) => {
    if (loaded && options.onLoaded) options.onLoaded()
  })
}

// --- Procedural Pattern Renderers ---

function _renderProceduralPattern(ctx, width, height, patternId, color, scale) {
  const key = proceduralCacheKey(patternId, color, scale, width, height)
  const cached = proceduralCache.get(key)
  if (cached) {
    ctx.drawImage(cached, 0, 0)
    return
  }

  // Render to offscreen canvas, then cache the result
  const offCanvas = document.createElement("canvas")
  offCanvas.width = width
  offCanvas.height = height
  const offCtx = offCanvas.getContext("2d")

  switch (patternId) {
    case "perlin_noise":
      _renderPerlinNoise(offCtx, width, height, color, scale)
      break
    case "confetti":
      _renderConfetti(offCtx, width, height, color, scale)
      break
    case "topography":
      _renderTopography(offCtx, width, height, color, scale)
      break
  }

  // Evict oldest entries if cache is full
  if (proceduralCache.size >= MAX_PROCEDURAL_CACHE) {
    const firstKey = proceduralCache.keys().next().value
    proceduralCache.delete(firstKey)
  }
  proceduralCache.set(key, offCanvas)

  ctx.drawImage(offCanvas, 0, 0)
}

// Simple seeded pseudo-random for deterministic patterns
function _seededRandom(seed) {
  let s = seed
  return function() {
    s = (s * 16807 + 0) % 2147483647
    return (s - 1) / 2147483646
  }
}

// Simplex-inspired noise (simplified)
function _simpleNoise(x, y) {
  const n = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return n - Math.floor(n)
}

function _smoothNoise(x, y, freq) {
  const fx = x * freq
  const fy = y * freq
  const ix = Math.floor(fx)
  const iy = Math.floor(fy)
  const fracX = fx - ix
  const fracY = fy - iy

  const v00 = _simpleNoise(ix, iy)
  const v10 = _simpleNoise(ix + 1, iy)
  const v01 = _simpleNoise(ix, iy + 1)
  const v11 = _simpleNoise(ix + 1, iy + 1)

  const i1 = v00 + (v10 - v00) * fracX
  const i2 = v01 + (v11 - v01) * fracX
  return i1 + (i2 - i1) * fracY
}

function _hexToRgb(hex) {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return { r, g, b }
}

function _renderPerlinNoise(ctx, width, height, color, scale) {
  const scaleF = (scale || 100) / 100
  const freq = 0.008 / scaleF
  const rgb = _hexToRgb(color)

  // Render at reduced resolution for performance, then scale up
  const res = 4
  const sw = Math.ceil(width / res)
  const sh = Math.ceil(height / res)
  const imageData = ctx.createImageData(sw, sh)
  const data = imageData.data

  for (let y = 0; y < sh; y++) {
    for (let x = 0; x < sw; x++) {
      const nx = x * res
      const ny = y * res
      const v = _smoothNoise(nx, ny, freq) * 0.5 +
                _smoothNoise(nx, ny, freq * 2) * 0.3 +
                _smoothNoise(nx, ny, freq * 4) * 0.2
      const alpha = Math.floor(v * 80)
      const idx = (y * sw + x) * 4
      data[idx] = rgb.r
      data[idx + 1] = rgb.g
      data[idx + 2] = rgb.b
      data[idx + 3] = alpha
    }
  }

  // Draw at reduced size, then scale up
  const tempCanvas = document.createElement("canvas")
  tempCanvas.width = sw
  tempCanvas.height = sh
  tempCanvas.getContext("2d").putImageData(imageData, 0, 0)

  ctx.imageSmoothingEnabled = true
  ctx.drawImage(tempCanvas, 0, 0, width, height)
}

function _renderConfetti(ctx, width, height, color, scale) {
  const scaleF = (scale || 100) / 100
  const rgb = _hexToRgb(color)
  const rand = _seededRandom(42)
  const count = Math.floor((width * height) / (800 * scaleF * scaleF))

  // Generate confetti colors as variations of the main color
  const colors = [
    color,
    `hsl(${(rand() * 360).toFixed(0)}, 70%, 60%)`,
    `hsl(${(rand() * 360).toFixed(0)}, 70%, 60%)`,
    `hsl(${(rand() * 360).toFixed(0)}, 70%, 60%)`,
    `hsl(${(rand() * 360).toFixed(0)}, 70%, 60%)`
  ]

  for (let i = 0; i < count; i++) {
    const x = rand() * width
    const y = rand() * height
    const w = (4 + rand() * 8) * scaleF
    const h = (2 + rand() * 4) * scaleF
    const angle = rand() * Math.PI * 2
    const confettiColor = colors[Math.floor(rand() * colors.length)]

    ctx.save()
    ctx.translate(x, y)
    ctx.rotate(angle)
    ctx.globalAlpha = 0.3 + rand() * 0.4
    ctx.fillStyle = confettiColor
    ctx.fillRect(-w / 2, -h / 2, w, h)
    ctx.restore()
  }
  ctx.globalAlpha = 1
}

function _renderTopography(ctx, width, height, color, scale) {
  const scaleF = (scale || 100) / 100
  const freq = 0.005 / scaleF
  const rgb = _hexToRgb(color)
  const levels = 10

  ctx.strokeStyle = color
  ctx.globalAlpha = 0.25
  ctx.lineWidth = 1

  // Draw contour lines by scanning and connecting points at same noise level
  for (let level = 1; level < levels; level++) {
    const threshold = level / levels

    ctx.beginPath()
    for (let y = 0; y < height; y += 3) {
      for (let x = 0; x < width; x += 3) {
        const v = _smoothNoise(x, y, freq) * 0.5 +
                  _smoothNoise(x, y, freq * 2) * 0.3 +
                  _smoothNoise(x, y, freq * 4) * 0.2
        const vr = _smoothNoise(x + 3, y, freq) * 0.5 +
                   _smoothNoise(x + 3, y, freq * 2) * 0.3 +
                   _smoothNoise(x + 3, y, freq * 4) * 0.2

        // Draw horizontal segments where contour crosses
        if ((v < threshold && vr >= threshold) || (v >= threshold && vr < threshold)) {
          const t = (threshold - v) / (vr - v)
          const cx = x + t * 3
          ctx.moveTo(cx, y)
          ctx.lineTo(cx + 1, y)
        }
      }
    }
    ctx.stroke()
  }

  ctx.globalAlpha = 1
}

/**
 * Clear the pattern cache. Call on controller disconnect.
 */
export function clearPatternCache() {
  patternCache.clear()
  imageCache.clear()
  pendingLoads.clear()
  failedLoads.clear()
  proceduralCache.clear()
}
