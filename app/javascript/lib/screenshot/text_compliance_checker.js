// Google Play text compliance checker
// Warns when text overlays exceed 20% of image area (Google Play requirement)

import { buildFontString, wrapText, measureTextWithSpacing } from "lib/screenshot/caption_renderer"

const GOOGLE_PLAY_TEXT_LIMIT = 0.20 // 20% of image area

/**
 * Calculate the percentage of canvas area occupied by text overlays.
 *
 * Considers:
 * - Title caption text
 * - Subtitle caption text
 * - Text background pill (if enabled, uses pill bounds instead of raw text)
 * - Text stickers (asset stickers with text overlays like speech/thought bubbles)
 *
 * @param {number} canvasWidth
 * @param {number} canvasHeight
 * @param {Object} captionOpts - caption options from _collectCaptionOpts
 * @param {Array} stickers - array of sticker objects
 * @returns {{ percentage: number, exceeds: boolean, limit: number }}
 */
export function calculateTextOverlayPercentage(canvasWidth, canvasHeight, captionOpts, stickers) {
  const canvasArea = canvasWidth * canvasHeight
  if (canvasArea === 0) return { percentage: 0, exceeds: false, limit: GOOGLE_PLAY_TEXT_LIMIT }

  let totalTextArea = 0

  // Measure caption group (title + subtitle)
  totalTextArea += measureCaptionGroupArea(canvasWidth, canvasHeight, captionOpts)

  // Measure text stickers (annotation bubbles with text)
  totalTextArea += measureTextStickerArea(canvasWidth, canvasHeight, stickers)

  const percentage = totalTextArea / canvasArea
  return {
    percentage,
    exceeds: percentage > GOOGLE_PLAY_TEXT_LIMIT,
    limit: GOOGLE_PLAY_TEXT_LIMIT
  }
}

/**
 * Measure the area occupied by the caption group (title + subtitle).
 * Uses an offscreen canvas for text measurement, matching the approach in caption_renderer.
 */
function measureCaptionGroupArea(canvasWidth, canvasHeight, opts) {
  if (!opts) return 0

  const hasTitle = opts.text && opts.text.trim()
  const hasSubtitle = opts.subtitleText && opts.subtitleText.trim()
  if (!hasTitle && !hasSubtitle) return 0

  // Create offscreen canvas for measurement
  const offscreen = document.createElement("canvas")
  offscreen.width = canvasWidth
  offscreen.height = canvasHeight
  const ctx = offscreen.getContext("2d")

  const scale = canvasWidth / 1080
  const maxWidth = canvasWidth * 0.85

  // Title measurement
  const titleFontSize = Math.round((opts.fontSize || 32) * scale)
  const titleFont = buildFontString(opts.fontWeight || 700, titleFontSize, opts.fontFamily || "Inter")
  const titleLineHeight = titleFontSize * (opts.lineHeight || 1.3)

  ctx.font = titleFont
  ctx.textAlign = opts.textAlign || "center"
  ctx.textBaseline = "middle"
  const titleLines = hasTitle ? wrapText(ctx, opts.text, maxWidth) : []
  const titleBlockHeight = titleLines.length * titleLineHeight

  // Subtitle measurement
  const subtitleFontSize = Math.round((opts.subtitleFontSize || 20) * scale)
  const subtitleFont = buildFontString(opts.subtitleFontWeight || 400, subtitleFontSize, opts.subtitleFontFamily || "Inter")
  const subtitleLineHeight = subtitleFontSize * (opts.subtitleLineHeight || 1.3)

  ctx.font = subtitleFont
  const subtitleLines = hasSubtitle ? wrapText(ctx, opts.subtitleText, maxWidth) : []
  const subtitleBlockHeight = subtitleLines.length * subtitleLineHeight

  // Gap between title and subtitle
  const gap = hasTitle && hasSubtitle ? titleFontSize * 0.3 : 0
  const totalTextHeight = titleBlockHeight + gap + subtitleBlockHeight

  // Measure max line width
  let maxLineWidth = 0
  const titleSpacing = (opts.letterSpacing || 0) * scale
  ctx.font = titleFont
  titleLines.forEach(line => {
    const w = measureTextWithSpacing(ctx, line, titleSpacing)
    if (w > maxLineWidth) maxLineWidth = w
  })
  const subtitleSpacing = (opts.subtitleLetterSpacing || 0) * scale
  ctx.font = subtitleFont
  subtitleLines.forEach(line => {
    const w = measureTextWithSpacing(ctx, line, subtitleSpacing)
    if (w > maxLineWidth) maxLineWidth = w
  })

  // If text background pill is enabled, use the padded bounds
  if (opts.textBgEnabled) {
    const padX = (opts.textBgPaddingX || 24) * scale
    const padY = (opts.textBgPaddingY || 12) * scale
    return (maxLineWidth + padX * 2) * (totalTextHeight + padY * 2)
  }

  return maxLineWidth * totalTextHeight
}

/**
 * Measure the area occupied by text-bearing stickers (annotation bubbles).
 * Only counts stickers that have text overlays rendered on them.
 */
function measureTextStickerArea(canvasWidth, canvasHeight, stickers) {
  if (!stickers || stickers.length === 0) return 0

  const scale = canvasWidth / 1080
  let totalArea = 0

  const textBubbleKeys = ["anno_speech_bubble", "anno_thought_bubble", "anno_callout_box"]

  for (const sticker of stickers) {
    const stickerType = sticker.type || "emoji"

    // Count asset stickers with text overlays
    if (stickerType === "asset" && sticker.text && textBubbleKeys.includes(sticker.asset_key)) {
      const pixelSize = sticker.size * scale
      // Approximate the text area as the sticker bounding box
      // (the text is rendered within the bubble, so the bubble area is the text overlay area)
      totalArea += pixelSize * pixelSize
    }
  }

  return totalArea
}

/**
 * Check whether the given platform requires Google Play compliance.
 * @param {string} platform - "android", "ios", or "both"
 * @returns {boolean}
 */
export function isGooglePlayPlatform(platform) {
  return platform === "android" || platform === "both"
}
