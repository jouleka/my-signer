// Emoji and grapheme utilities for screenshot editor
// Uses Intl.Segmenter for correct Unicode grapheme cluster handling

const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" })

const emojiRegex = /\p{Extended_Pictographic}/u

export function segmentGraphemes(text) {
  return Array.from(segmenter.segment(text), s => s.segment)
}

export function graphemeCount(text) {
  let count = 0
  for (const _ of segmenter.segment(text)) count++
  return count
}

export function isEmojiGrapheme(grapheme) {
  return emojiRegex.test(grapheme)
}

export function hasEmoji(text) {
  return emojiRegex.test(text)
}
