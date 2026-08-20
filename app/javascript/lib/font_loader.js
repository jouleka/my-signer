const loadedCSS = new Set()
const loadingPromises = new Map()

const ALLOWED_WEIGHTS = new Set([300, 400, 500, 600, 700, 800, 900])

function normalizeWeight(weight) {
  const parsed = Number.parseInt(weight, 10)
  return ALLOWED_WEIGHTS.has(parsed) ? parsed : 400
}

function buildFontHref(family, weights = [400]) {
  const normalized = [...new Set(weights.map(normalizeWeight))].sort((a, b) => a - b)
  const encoded = family.replace(/ /g, "+")
  return `https://fonts.googleapis.com/css2?family=${encoded}:wght@${normalized.join(";")}&display=swap`
}

export function ensureCSSLink(family, weights = [400]) {
  const href = buildFontHref(family, weights)
  if (loadedCSS.has(href)) return
  loadedCSS.add(href)

  if (document.querySelector(`link[href="${href}"]`)) return

  const link = document.createElement("link")
  link.rel = "stylesheet"
  link.href = href
  document.head.appendChild(link)
}

export async function loadFontForCanvas(family, weight = 400) {
  const normalizedWeight = normalizeWeight(weight)
  const key = `${family}:${normalizedWeight}`
  if (loadingPromises.has(key)) return loadingPromises.get(key)

  const promise = (async () => {
    ensureCSSLink(family, [normalizedWeight])

    const fontSpec = `${normalizedWeight} 16px "${family}"`
    if (document.fonts.check(fontSpec)) return

    try {
      await Promise.race([
        document.fonts.ready,
        new Promise((_, reject) => setTimeout(() => reject(new Error("Font load timeout")), 5000))
      ])
    } catch (e) {
      console.warn(`Font load timeout for ${family} ${weight}`)
    }

    // Extra check after fonts.ready
    let attempts = 0
    while (!document.fonts.check(fontSpec) && attempts < 10) {
      await new Promise(r => setTimeout(r, 100))
      attempts++
    }
  })()

  loadingPromises.set(key, promise)
  return promise
}

export async function preloadFonts(families) {
  const promises = families.map(f => loadFontForCanvas(f, 400))
  await Promise.allSettled(promises)
}
