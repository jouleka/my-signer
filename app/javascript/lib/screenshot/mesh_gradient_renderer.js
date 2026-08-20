// Mesh gradient renderer — 12 curated presets with radial gradient blob overlays

export const MESH_PRESETS = {
  sunset: {
    label: "Sunset",
    base: "#1a0533",
    blobs: [
      { x: 0.2, y: 0.3, radius: 0.6, color: "#FF6B35" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#F7931E" },
      { x: 0.5, y: 0.8, radius: 0.55, color: "#D4145A" },
      { x: 0.9, y: 0.6, radius: 0.45, color: "#FBB03B" }
    ]
  },
  ocean: {
    label: "Ocean",
    base: "#0a1628",
    blobs: [
      { x: 0.3, y: 0.2, radius: 0.6, color: "#0077B6" },
      { x: 0.7, y: 0.5, radius: 0.55, color: "#00B4D8" },
      { x: 0.2, y: 0.7, radius: 0.5, color: "#023E8A" },
      { x: 0.8, y: 0.8, radius: 0.4, color: "#48CAE4" }
    ]
  },
  aurora: {
    label: "Aurora",
    base: "#0B0B1A",
    blobs: [
      { x: 0.2, y: 0.4, radius: 0.6, color: "#00C9A7" },
      { x: 0.6, y: 0.2, radius: 0.5, color: "#845EC2" },
      { x: 0.8, y: 0.7, radius: 0.55, color: "#00B8A9" },
      { x: 0.4, y: 0.8, radius: 0.45, color: "#4B7BE5" },
      { x: 0.1, y: 0.1, radius: 0.35, color: "#2C73D2" }
    ]
  },
  lavender: {
    label: "Lavender",
    base: "#1A1025",
    blobs: [
      { x: 0.3, y: 0.3, radius: 0.6, color: "#9B59B6" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#8E44AD" },
      { x: 0.5, y: 0.7, radius: 0.55, color: "#D4A5FF" },
      { x: 0.2, y: 0.8, radius: 0.4, color: "#6C3483" }
    ]
  },
  coral: {
    label: "Coral",
    base: "#1A0A0A",
    blobs: [
      { x: 0.3, y: 0.3, radius: 0.6, color: "#FF6F61" },
      { x: 0.7, y: 0.5, radius: 0.5, color: "#FF9671" },
      { x: 0.5, y: 0.8, radius: 0.55, color: "#FFC75F" },
      { x: 0.2, y: 0.6, radius: 0.4, color: "#F9484A" }
    ]
  },
  forest: {
    label: "Forest",
    base: "#0A1A0A",
    blobs: [
      { x: 0.3, y: 0.3, radius: 0.6, color: "#2D6A4F" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#40916C" },
      { x: 0.5, y: 0.7, radius: 0.55, color: "#52B788" },
      { x: 0.8, y: 0.8, radius: 0.4, color: "#1B4332" },
      { x: 0.1, y: 0.6, radius: 0.35, color: "#74C69D" }
    ]
  },
  candy: {
    label: "Candy",
    base: "#1A0820",
    blobs: [
      { x: 0.2, y: 0.3, radius: 0.6, color: "#FF6B9D" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#C44DFF" },
      { x: 0.5, y: 0.8, radius: 0.55, color: "#FF85A1" },
      { x: 0.8, y: 0.6, radius: 0.45, color: "#FFC2D1" }
    ]
  },
  midnight: {
    label: "Midnight",
    base: "#050510",
    blobs: [
      { x: 0.3, y: 0.3, radius: 0.6, color: "#1A1A4E" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#2D2D7F" },
      { x: 0.5, y: 0.7, radius: 0.55, color: "#15154B" },
      { x: 0.8, y: 0.8, radius: 0.4, color: "#4040B0" }
    ]
  },
  neon: {
    label: "Neon",
    base: "#0A0A0A",
    blobs: [
      { x: 0.2, y: 0.3, radius: 0.55, color: "#00FF87" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#FF00E5" },
      { x: 0.5, y: 0.8, radius: 0.55, color: "#00D4FF" },
      { x: 0.9, y: 0.6, radius: 0.4, color: "#FFE500" },
      { x: 0.1, y: 0.7, radius: 0.35, color: "#7B61FF" }
    ]
  },
  peach: {
    label: "Peach",
    base: "#1A1008",
    blobs: [
      { x: 0.3, y: 0.3, radius: 0.6, color: "#FFBE76" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#FF9F43" },
      { x: 0.5, y: 0.7, radius: 0.55, color: "#FECA57" },
      { x: 0.2, y: 0.8, radius: 0.4, color: "#F0932B" }
    ]
  },
  arctic: {
    label: "Arctic",
    base: "#0A1520",
    blobs: [
      { x: 0.3, y: 0.3, radius: 0.6, color: "#74B9FF" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#A29BFE" },
      { x: 0.5, y: 0.7, radius: 0.55, color: "#81ECEC" },
      { x: 0.8, y: 0.8, radius: 0.4, color: "#DFE6E9" }
    ]
  },
  ember: {
    label: "Ember",
    base: "#1A0800",
    blobs: [
      { x: 0.2, y: 0.3, radius: 0.6, color: "#E74C3C" },
      { x: 0.7, y: 0.2, radius: 0.5, color: "#E67E22" },
      { x: 0.5, y: 0.8, radius: 0.55, color: "#C0392B" },
      { x: 0.9, y: 0.6, radius: 0.45, color: "#F39C12" },
      { x: 0.1, y: 0.7, radius: 0.35, color: "#D35400" }
    ]
  }
}

/**
 * Render a mesh gradient on a canvas context.
 * Uses radial gradients with "screen" composite for a soft, blended look.
 *
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} width
 * @param {number} height
 * @param {string} presetKey - key from MESH_PRESETS
 * @param {object} colorOverrides - { mesh_color_1, mesh_color_2, mesh_color_3 }
 */
export function renderMeshGradient(ctx, width, height, presetKey, colorOverrides = {}) {
  const preset = MESH_PRESETS[presetKey]
  if (!preset) {
    ctx.fillStyle = "#000000"
    ctx.fillRect(0, 0, width, height)
    return
  }

  // Fill base color
  ctx.fillStyle = preset.base
  ctx.fillRect(0, 0, width, height)

  // Save composite mode
  const prevComposite = ctx.globalCompositeOperation
  ctx.globalCompositeOperation = "screen"

  const blobs = preset.blobs
  const overrideColors = [
    colorOverrides.mesh_color_1,
    colorOverrides.mesh_color_2,
    colorOverrides.mesh_color_3
  ]

  for (let i = 0; i < blobs.length; i++) {
    const blob = blobs[i]
    const color = (i < 3 && overrideColors[i]) ? overrideColors[i] : blob.color

    const cx = blob.x * width
    const cy = blob.y * height
    const maxDim = Math.max(width, height)
    const r = blob.radius * maxDim

    const gradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
    gradient.addColorStop(0, color)
    gradient.addColorStop(1, "transparent")

    ctx.fillStyle = gradient
    ctx.fillRect(0, 0, width, height)
  }

  // Restore composite mode
  ctx.globalCompositeOperation = prevComposite
}

/**
 * Generate a CSS approximation of a mesh gradient for template previews.
 * Returns a CSS background string.
 */
export function meshPresetToCSS(presetKey, colorOverrides = {}) {
  const preset = MESH_PRESETS[presetKey]
  if (!preset) return "#000000"

  const overrideColors = [
    colorOverrides.mesh_color_1,
    colorOverrides.mesh_color_2,
    colorOverrides.mesh_color_3
  ]

  const layers = preset.blobs.map((blob, i) => {
    const color = (i < 3 && overrideColors[i]) ? overrideColors[i] : blob.color
    const x = (blob.x * 100).toFixed(0)
    const y = (blob.y * 100).toFixed(0)
    const size = (blob.radius * 200).toFixed(0)
    return `radial-gradient(circle ${size}% at ${x}% ${y}%, ${color}, transparent)`
  })

  return `${layers.join(", ")}, ${preset.base}`
}
