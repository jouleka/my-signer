// SVG sticker image cache — loads SVGs, applies color tinting, caches as Image objects

const imageCache = new Map()   // cacheKey -> Image
const blobUrlCache = new Map() // cacheKey -> blob URL (revoked on eviction)
const pendingLoads = new Map()
const failedLoads = new Map() // cacheKey -> retryAfter timestamp (ms)
const MAX_CACHE_SIZE = 200
const FAILED_RETRY_DELAY_MS = 10_000

function evictEntry(key) {
  imageCache.delete(key)
  const blobUrl = blobUrlCache.get(key)
  if (blobUrl) {
    URL.revokeObjectURL(blobUrl)
    blobUrlCache.delete(key)
  }
}

function evictIfNeeded() {
  if (imageCache.size <= MAX_CACHE_SIZE) return
  const keysToDelete = Array.from(imageCache.keys()).slice(0, imageCache.size - MAX_CACHE_SIZE)
  for (const key of keysToDelete) {
    evictEntry(key)
  }
}

/**
 * Clear all cached images and pending loads.
 * Call from controller disconnect() to prevent memory leaks.
 */
export function clearCache() {
  for (const blobUrl of blobUrlCache.values()) {
    URL.revokeObjectURL(blobUrl)
  }
  imageCache.clear()
  blobUrlCache.clear()
  pendingLoads.clear()
  failedLoads.clear()
}

/**
 * Get a cached sticker Image for the given asset key and color.
 * Returns the Image if cached, or null if not yet loaded.
 */
export function getStickerImage(assetKey, color) {
  const cacheKey = `${assetKey}_${color || "#FFFFFF"}`
  const entry = imageCache.get(cacheKey)
  return entry && entry.complete ? entry : null
}

/**
 * Load an SVG sticker image, apply color tinting, and cache it.
 * Returns a Promise that resolves to the Image.
 */
export async function loadStickerImage(assetKey, imageUrl, color) {
  const normalizedColor = color || "#FFFFFF"
  const cacheKey = `${assetKey}_${normalizedColor}`
  if (!imageUrl) return null

  // Already cached
  const existing = imageCache.get(cacheKey)
  if (existing && existing.complete) return existing

  // Recently failed (avoid repeated retries; allow eventual recovery)
  const retryAfter = failedLoads.get(cacheKey)
  if (retryAfter && Date.now() < retryAfter) return null
  if (retryAfter) failedLoads.delete(cacheKey)

  // Already loading
  const pending = pendingLoads.get(cacheKey)
  if (pending) return pending

  const loadPromise = (async () => {
    try {
      const response = await fetch(imageUrl)
      if (!response.ok) throw new Error(`Failed to fetch ${imageUrl}: ${response.status}`)
      let svgText = await response.text()

      // Apply color tint
      svgText = recolorSvg(svgText, normalizedColor)

      // Create Image from SVG blob
      const blob = new Blob([svgText], { type: "image/svg+xml" })
      const url = URL.createObjectURL(blob)

      return new Promise((resolve) => {
        const img = new Image()
        img.onload = () => {
          imageCache.set(cacheKey, img)
          blobUrlCache.set(cacheKey, url)
          failedLoads.delete(cacheKey)
          evictIfNeeded()
          pendingLoads.delete(cacheKey)
          resolve(img)
        }
        img.onerror = () => {
          failedLoads.set(cacheKey, Date.now() + FAILED_RETRY_DELAY_MS)
          pendingLoads.delete(cacheKey)
          URL.revokeObjectURL(url)
          console.warn(`[sticker_image_cache] Failed to decode ${assetKey}`)
          resolve(null)
        }
        img.src = url
      })
    } catch (err) {
      failedLoads.set(cacheKey, Date.now() + FAILED_RETRY_DELAY_MS)
      pendingLoads.delete(cacheKey)
      console.warn(`[sticker_image_cache] Error loading ${assetKey}:`, err)
      return null
    }
  })()

  pendingLoads.set(cacheKey, loadPromise)
  return loadPromise
}

/**
 * Preload all asset-type sticker images for a list of stickers.
 * Resolves when all images are loaded (or failed gracefully).
 */
export async function preloadStickerImages(stickers, library) {
  if (!stickers || !library) return

  // Build a lookup of asset_key -> image_url from the library
  const urlMap = {}
  for (const category of Object.values(library)) {
    if (!category.items) continue
    for (const item of category.items) {
      urlMap[item.key] = item.image_url
    }
  }

  const promises = stickers.map(s => {
    const sType = s.type || "emoji"

    if (sType === "asset") {
      const url = urlMap[s.asset_key]
      if (!url) return Promise.resolve(null)
      return loadStickerImage(s.asset_key, url, s.color || "#FFFFFF")
    }

    return Promise.resolve(null)
  })

  await Promise.allSettled(promises)
}

/**
 * Preload the entire sticker library for a given color.
 * Used for eager loading when switching to the Library tab.
 */
const PRELOAD_BATCH_SIZE = 6

export async function preloadEntireLibrary(library, color) {
  if (!library) return

  const normalizedColor = color || "#FFFFFF"
  const items = []

  for (const category of Object.values(library)) {
    if (!category.items) continue
    for (const item of category.items) {
      if (item.image_url) {
        items.push(item)
      }
    }
  }

  for (let i = 0; i < items.length; i += PRELOAD_BATCH_SIZE) {
    const batch = items.slice(i, i + PRELOAD_BATCH_SIZE)
    await Promise.allSettled(batch.map(item => loadStickerImage(item.key, item.image_url, normalizedColor)))
  }
}

/**
 * Compute relative luminance of a hex color (0 = black, 1 = white).
 */
function luminance(hex) {
  const r = parseInt(hex.slice(1, 3), 16) / 255
  const g = parseInt(hex.slice(3, 5), 16) / 255
  const b = parseInt(hex.slice(5, 7), 16) / 255
  const toLinear = (c) => c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  return 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b)
}

/**
 * Recolor an SVG string by replacing stroke and fill colors.
 * Works for Lucide-style single-color stroke icons and simple SVGs.
 * Also handles style-attribute-based currentColor references.
 *
 * For annotation-style SVGs that use hardcoded "white" as inner element color
 * (e.g. numbered circles, checkmarks), automatically swaps to a contrasting
 * color when the target color is too light.
 */
export function recolorSvg(svgText, color) {
  // Replace stroke="currentColor" with the target color
  let result = svgText.replace(/stroke="currentColor"/g, `stroke="${color}"`)
  // Replace fill="currentColor" with the target color
  result = result.replace(/fill="currentColor"/g, `fill="${color}"`)
  // Handle style-attribute-based currentColor (e.g., style="stroke: currentColor")
  result = result.replace(/stroke:\s*currentColor/gi, `stroke: ${color}`)
  result = result.replace(/fill:\s*currentColor/gi, `fill: ${color}`)

  // Swap hardcoded white inner elements to a contrasting color when the
  // main color is light (e.g. white numbered circle needs dark numbers)
  const contrastColor = luminance(color) > 0.4 ? "#1a1a2e" : "white"
  if (contrastColor !== "white") {
    result = result.replace(/fill="white"/g, `fill="${contrastColor}"`)
    result = result.replace(/stroke="white"/g, `stroke="${contrastColor}"`)
  }

  return result
}
