// Dark mode color transformation utilities
// Converts light scene settings to dark equivalents and vice versa.

/**
 * Parse a hex color string (#RRGGBB or #RGB) to { r, g, b } (0-255).
 */
function hexToRgb(hex) {
  hex = hex.replace(/^#/, "")
  if (hex.length === 3) {
    hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2]
  }
  return {
    r: parseInt(hex.slice(0, 2), 16),
    g: parseInt(hex.slice(2, 4), 16),
    b: parseInt(hex.slice(4, 6), 16)
  }
}

/**
 * Convert { r, g, b } (0-255) back to a #RRGGBB hex string.
 */
function rgbToHex({ r, g, b }) {
  const toHex = (v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`
}

/**
 * Convert RGB (0-255) to HSL (h: 0-360, s: 0-1, l: 0-1).
 */
function rgbToHsl({ r, g, b }) {
  r /= 255; g /= 255; b /= 255
  const max = Math.max(r, g, b), min = Math.min(r, g, b)
  let h = 0, s = 0
  const l = (max + min) / 2

  if (max !== min) {
    const d = max - min
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break
      case g: h = ((b - r) / d + 2) / 6; break
      case b: h = ((r - g) / d + 4) / 6; break
    }
  }
  return { h: h * 360, s, l }
}

/**
 * Convert HSL (h: 0-360, s: 0-1, l: 0-1) to RGB (0-255).
 */
function hslToRgb({ h, s, l }) {
  h /= 360
  let r, g, b

  if (s === 0) {
    r = g = b = l
  } else {
    const hue2rgb = (p, q, t) => {
      if (t < 0) t += 1
      if (t > 1) t -= 1
      if (t < 1/6) return p + (q - p) * 6 * t
      if (t < 1/2) return q
      if (t < 2/3) return p + (q - p) * (2/3 - t) * 6
      return p
    }
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s
    const p = 2 * l - q
    r = hue2rgb(p, q, h + 1/3)
    g = hue2rgb(p, q, h)
    b = hue2rgb(p, q, h - 1/3)
  }

  return { r: Math.round(r * 255), g: Math.round(g * 255), b: Math.round(b * 255) }
}

/**
 * Perceived luminance (0-1) of a hex color.
 */
function luminance(hex) {
  const { r, g, b } = hexToRgb(hex)
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255
}

/**
 * Returns true if the color is considered "light" (luminance > 0.5).
 */
function isLight(hex) {
  return luminance(hex) > 0.5
}

/**
 * Invert a color's lightness while preserving hue and saturation.
 * Light colors become dark; dark colors become light.
 */
function invertLightness(hex) {
  const rgb = hexToRgb(hex)
  const hsl = rgbToHsl(rgb)
  hsl.l = 1 - hsl.l
  return rgbToHex(hslToRgb(hsl))
}

/**
 * Create a dark variant of a color: shift lightness toward the dark end.
 * For already-dark colors, returns them mostly as-is (slight adjustment).
 */
function toDark(hex) {
  const rgb = hexToRgb(hex)
  const hsl = rgbToHsl(rgb)
  if (hsl.l > 0.5) {
    // Light color -> make it dark. Mirror lightness around 0.5 then compress.
    hsl.l = Math.max(0.05, 1 - hsl.l - 0.1)
  } else if (hsl.l > 0.3) {
    // Medium color -> darken it
    hsl.l = Math.max(0.05, hsl.l - 0.25)
  }
  // Already dark -> leave as-is
  return rgbToHex(hslToRgb(hsl))
}

/**
 * Create a light variant of a color: shift lightness toward the light end.
 * For already-light colors, returns them mostly as-is.
 */
function toLight(hex) {
  const rgb = hexToRgb(hex)
  const hsl = rgbToHsl(rgb)
  if (hsl.l < 0.5) {
    // Dark color -> make it light. Mirror lightness around 0.5 then compress.
    hsl.l = Math.min(0.95, 1 - hsl.l + 0.1)
  } else if (hsl.l < 0.7) {
    // Medium color -> lighten it
    hsl.l = Math.min(0.95, hsl.l + 0.25)
  }
  // Already light -> leave as-is
  return rgbToHex(hslToRgb(hsl))
}

/**
 * Generate a dark-mode variant of the given scene settings object.
 * Returns a new settings object with transformed colors.
 *
 * @param {object} settings - The current scene settings (from getCurrentSettings())
 * @returns {object} - A new settings object with dark-mode colors
 */
export function generateDarkVariant(settings) {
  const s = { ...settings }
  const bgType = s.background_type || "solid"

  // --- Transform background colors ---
  switch (bgType) {
    case "solid":
      if (s.background_color) {
        s.background_color = isLight(s.background_color)
          ? toDark(s.background_color)
          : invertLightness(s.background_color)
      }
      break

    case "gradient":
      if (s.gradient_start) s.gradient_start = toDark(s.gradient_start)
      if (s.gradient_end) s.gradient_end = toDark(s.gradient_end)
      break

    case "pattern":
      // Swap pattern color and bg color for dark mode
      if (s.pattern_color && s.pattern_bg_color) {
        const origColor = s.pattern_color
        const origBg = s.pattern_bg_color
        // If bg is dark and pattern is light, swap. Otherwise invert both.
        if (isLight(origBg) && !isLight(origColor)) {
          s.pattern_bg_color = origColor
          s.pattern_color = origBg
        } else if (!isLight(origBg) && isLight(origColor)) {
          // Already dark-on-light pattern — make bg darker, keep pattern light
          s.pattern_bg_color = toDark(origBg)
          s.pattern_color = toLight(origColor)
        } else {
          s.pattern_bg_color = toDark(origBg)
          s.pattern_color = toLight(origColor)
        }
      }
      break

    // Mesh presets are already dark-based — no transform needed
    case "mesh":
    case "image":
    case "panoramic":
    case "none":
      break
  }

  // --- Transform text colors ---
  // Caption color: if it was dark text, make it light
  if (s.caption_color) {
    if (!isLight(s.caption_color)) {
      s.caption_color = toLight(s.caption_color)
    } else {
      // If caption was light and background was also light (now dark), keep it light
      // If caption was light and background was dark, make it dark (we inverted bg)
      const origBgLight = _wasOriginalBgLight(settings)
      if (!origBgLight) {
        s.caption_color = toDark(s.caption_color)
      }
    }
  }

  if (s.subtitle_color) {
    if (!isLight(s.subtitle_color)) {
      s.subtitle_color = toLight(s.subtitle_color)
    } else {
      const origBgLight = _wasOriginalBgLight(settings)
      if (!origBgLight) {
        s.subtitle_color = toDark(s.subtitle_color)
      }
    }
  }

  // --- Text background ---
  if (s.text_bg_color) {
    s.text_bg_color = invertLightness(s.text_bg_color)
  }

  // --- Stroke color ---
  if (s.caption_stroke_color) {
    s.caption_stroke_color = invertLightness(s.caption_stroke_color)
  }

  return s
}

/**
 * Generate a light-mode variant of the given scene settings object.
 * Returns a new settings object with transformed colors.
 *
 * @param {object} settings - The current scene settings
 * @returns {object} - A new settings object with light-mode colors
 */
export function generateLightVariant(settings) {
  const s = { ...settings }
  const bgType = s.background_type || "solid"

  switch (bgType) {
    case "solid":
      if (s.background_color) {
        s.background_color = !isLight(s.background_color)
          ? toLight(s.background_color)
          : invertLightness(s.background_color)
      }
      break

    case "gradient":
      if (s.gradient_start) s.gradient_start = toLight(s.gradient_start)
      if (s.gradient_end) s.gradient_end = toLight(s.gradient_end)
      break

    case "pattern":
      if (s.pattern_color && s.pattern_bg_color) {
        const origColor = s.pattern_color
        const origBg = s.pattern_bg_color
        if (!isLight(origBg) && isLight(origColor)) {
          s.pattern_bg_color = origColor
          s.pattern_color = origBg
        } else {
          s.pattern_bg_color = toLight(origBg)
          s.pattern_color = toDark(origColor)
        }
      }
      break

    case "mesh":
    case "image":
    case "panoramic":
    case "none":
      break
  }

  // Text colors: make them dark for light backgrounds
  if (s.caption_color) {
    if (isLight(s.caption_color)) {
      s.caption_color = toDark(s.caption_color)
    } else {
      const origBgDark = !_wasOriginalBgLight(settings)
      if (!origBgDark) {
        s.caption_color = toLight(s.caption_color)
      }
    }
  }

  if (s.subtitle_color) {
    if (isLight(s.subtitle_color)) {
      s.subtitle_color = toDark(s.subtitle_color)
    } else {
      const origBgDark = !_wasOriginalBgLight(settings)
      if (!origBgDark) {
        s.subtitle_color = toLight(s.subtitle_color)
      }
    }
  }

  if (s.text_bg_color) {
    s.text_bg_color = invertLightness(s.text_bg_color)
  }

  if (s.caption_stroke_color) {
    s.caption_stroke_color = invertLightness(s.caption_stroke_color)
  }

  return s
}

/**
 * Determine if the original background was perceived as "light".
 */
function _wasOriginalBgLight(settings) {
  const bgType = settings.background_type || "solid"
  switch (bgType) {
    case "solid":
      return settings.background_color ? isLight(settings.background_color) : false
    case "gradient":
      // Average the two gradient stops
      if (settings.gradient_start && settings.gradient_end) {
        return (luminance(settings.gradient_start) + luminance(settings.gradient_end)) / 2 > 0.5
      }
      return false
    case "pattern":
      return settings.pattern_bg_color ? isLight(settings.pattern_bg_color) : false
    case "mesh":
      return false // mesh presets are all dark-based
    default:
      return false
  }
}

/**
 * Detect whether the current settings represent a "dark" scene.
 * Uses background color luminance as primary signal.
 */
export function isDarkScene(settings) {
  return !_wasOriginalBgLight(settings)
}
