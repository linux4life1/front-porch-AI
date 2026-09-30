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
