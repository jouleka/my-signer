// Custom image cache — loads raster images (PNG/JPEG/WebP) and caches as Image objects
// Separate from SVG sticker_image_cache since no recoloring is needed

const imageCache = new Map()   // url -> Image
const pendingLoads = new Map() // url -> Promise<Image>
const failedLoads = new Map()  // url -> retryAfter timestamp (ms)
const FAILED_RETRY_DELAY_MS = 10_000
const MAX_CACHE_SIZE = 120

function evictIfNeeded(pinnedUrl = null) {
  while (imageCache.size > MAX_CACHE_SIZE) {
    const oldestUrl = imageCache.keys().next().value
    if (!oldestUrl) break
    if (oldestUrl === pinnedUrl && imageCache.size > 1) {
      const pinned = imageCache.get(oldestUrl)
      imageCache.delete(oldestUrl)
      imageCache.set(oldestUrl, pinned)
      continue
    }
    imageCache.delete(oldestUrl)
  }
}

/**
 * Clear all cached images and pending loads.
 * Call from controller disconnect() to prevent memory leaks.
 */
export function clearCustomImageCache() {
  imageCache.clear()
  pendingLoads.clear()
  failedLoads.clear()
}

/**
 * Get a cached custom Image for the given URL.
 * Returns the Image if cached and loaded, or null if not yet loaded.
 */
export function getCustomImage(url) {
  const img = imageCache.get(url)
  if (!img || !img.complete) return null
  // Refresh recency on access so active sticker images stay resident.
  imageCache.delete(url)
  imageCache.set(url, img)
  return img
}

/**
 * Load a custom image from URL and cache it.
 * Returns a Promise that resolves to the Image.
 */
export function loadCustomImage(url) {
  if (!url) return Promise.reject(new Error("Failed to load custom image: missing URL"))

  // Already cached
  const existing = imageCache.get(url)
  if (existing && existing.complete) return Promise.resolve(existing)

  // Recently failed (avoid repeated noisy retries while still allowing eventual retry)
  const retryAfter = failedLoads.get(url)
  if (retryAfter && Date.now() < retryAfter) {
    return Promise.reject(new Error(`Failed to load custom image: ${url}`))
  }
  if (retryAfter) failedLoads.delete(url)

  // Already loading
  const pending = pendingLoads.get(url)
  if (pending) return pending

  const loadPromise = new Promise((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = "anonymous"
    img.onload = () => {
      imageCache.set(url, img)
      evictIfNeeded(url)
      failedLoads.delete(url)
      pendingLoads.delete(url)
      resolve(img)
    }
    img.onerror = () => {
      imageCache.delete(url)
      failedLoads.set(url, Date.now() + FAILED_RETRY_DELAY_MS)
      pendingLoads.delete(url)
      reject(new Error(`Failed to load custom image: ${url}`))
    }
    img.src = url
  })

  pendingLoads.set(url, loadPromise)
  return loadPromise
}

/**
 * Preload all custom_image-type sticker images for a list of stickers.
 * Resolves when all images are loaded (or failed gracefully).
 */
export async function preloadCustomImages(stickers) {
  if (!stickers) return

  const promises = stickers
    .filter(s => s.type === "custom_image" && s.image_url)
    .map(s => loadCustomImage(s.image_url).catch(() => null))

  await Promise.allSettled(promises)
}
