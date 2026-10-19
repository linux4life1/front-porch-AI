// Mounted slice of a transcript. Mirrors
// lib/ui/chat_components/stage/transcript_window.dart — a long chat
// stays on its latest lines until the reader scrolls up.

export const TRANSCRIPT_TAIL = 24
export const TRANSCRIPT_REVEAL = 24

export type TranscriptSpan = { start: number; end: number }

export function applyTranscriptSpan(
  span: TranscriptSpan,
  args: {
    previousLength: number
    nextLength: number
    opened: boolean
    prepended: boolean
    nearTop: boolean
  },
): void {
  const { previousLength, nextLength, opened, prepended, nearTop } = args
  if (nextLength <= 0) {
    span.start = 0
    span.end = 0
    return
  }
  if (opened || previousLength <= 0) {
    span.end = nextLength
    span.start = nextLength > TRANSCRIPT_TAIL ? nextLength - TRANSCRIPT_TAIL : 0
    return
  }
  if (nextLength > previousLength && prepended) {
    const added = nextLength - previousLength
    if (nearTop) span.end += added
    else {
      span.start += added
      span.end += added
    }
  } else if (nextLength > previousLength) {
    if (span.end >= previousLength) span.end = nextLength
  } else if (nextLength < previousLength && span.end >= previousLength) {
    span.end = nextLength
  }
  clampTranscriptSpan(span, nextLength)
}

export function revealOlderSpan(span: TranscriptSpan, fullLength: number, page = TRANSCRIPT_REVEAL): boolean {
  if (span.start <= 0 || fullLength <= 0) return false
  span.start = span.start > page ? span.start - page : 0
  clampTranscriptSpan(span, fullLength)
  return true
}

/** Put [index] inside the mounted span — ⌘F navigation (mirrors Dart
 * TranscriptWindow.revealAround). The find bar scrolls to the row after
 * this runs; without it a match outside the tail is simply not mounted. */
export function revealAroundSpan(span: TranscriptSpan, index: number, fullLength: number): boolean {
  if (fullLength <= 0) return false
  const i = Math.max(0, Math.min(index, fullLength - 1))
  if (i >= span.start && i < span.end) return false
  let nextEnd = Math.min(i + TRANSCRIPT_TAIL / 2, fullLength)
  if (nextEnd < i + 1) nextEnd = i + 1
  let nextStart = Math.max(nextEnd - TRANSCRIPT_TAIL, 0)
  if (i < nextStart) nextStart = i
  if (i >= nextEnd) nextEnd = i + 1
  span.start = nextStart
  span.end = nextEnd
  clampTranscriptSpan(span, fullLength)
  return true
}

function clampTranscriptSpan(span: TranscriptSpan, fullLength: number): void {
  if (fullLength <= 0) {
    span.start = 0
    span.end = 0
    return
  }
  if (span.end > fullLength) span.end = fullLength
  if (span.end < 0) span.end = 0
  if (span.start < 0) span.start = 0
  if (span.start > span.end) span.start = span.end
  if (span.start === span.end && span.end > 0) span.start = span.end - 1
}
